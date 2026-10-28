defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TierRunner do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.ExecutionAccess
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TierRuns
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.ReplicaTiming
  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.{StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  # One tier run of Final collection.
  #
  # The tier row is created or reused under the execution lock, so two
  # coordinators cannot declare the same position twice. Linking and dispatch
  # take the execution lock first and the phase-run lock second. The wait for
  # Gust stays outside every lock, so a timing marker and a cancellation wake-up
  # can reach the coordinator process.
  #
  # The stored run is authoritative: a row that already links a run keeps it, and
  # the returned timings are accepted only after the stored state, the persisted
  # receipt, and the measured positions agree.
  @spec run(IO.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, [ReplicaTiming.t()]} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{} = io, tier, tier_position, opts) do
    workflow = Keyword.fetch!(opts, :workflow)
    timeout = Keyword.fetch!(opts, :timeout)
    execution_id = io.execution.id

    with {:ok, phase, phase_run} <- prepare(execution_id, tier, tier_position),
         tier_io = tier_io(io, phase, phase_run),
         {:ok, gust_run_id} <- run_id(workflow, tier_io),
         {:ok, tier_io} <- link(execution_id, tier_io, gust_run_id),
         :ok <- dispatch(execution_id, tier_io, workflow),
         {:ok, timings} <- await(workflow, tier_io, timeout),
         :ok <- receipt(workflow, tier_io),
         :ok <- measured_positions(tier, timings) do
      {:ok, timings}
    end
  end

  defp tier_io(%IO{} = io, %StudyPhase{} = phase, %StudyPhaseRun{} = phase_run) do
    %IO.Tier{
      execution: io.execution,
      phase: phase,
      definition: io.definition,
      tier: phase_run.tier,
      tier_position: phase_run.tier_position,
      phase_run: phase_run
    }
  end

  defp prepare(execution_id, tier, tier_position) do
    State.transaction(execution_id, &locked_prepare(&1, tier, tier_position))
  end

  defp locked_prepare(%{state: :collecting_final} = execution, tier, tier_position) do
    phase = State.lock_named_phase(execution.id, :final_collection)

    case TierRuns.get_or_create(phase, tier, tier_position) do
      {:ok, %StudyPhaseRun{tier: ^tier, tier_position: ^tier_position} = phase_run} ->
        {:ok, phase, phase_run}

      {:ok, %StudyPhaseRun{}} ->
        Repo.rollback({:error, StudyError.phase_run_conflict()})

      {:error, %StudyError{} = error} ->
        Repo.rollback({:error, error})
    end
  end

  defp locked_prepare(%{state: state}, _tier, _tier_position), do: State.stop(state)

  defp run_id(workflow, %IO.Tier{phase_run: %StudyPhaseRun{gust_run_id: nil}} = tier_io) do
    case workflow.create(tier_io) do
      {:ok, run_id} when is_integer(run_id) and run_id > 0 -> {:ok, run_id}
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  end

  defp run_id(_workflow, %IO.Tier{phase_run: %StudyPhaseRun{gust_run_id: run_id}})
       when is_integer(run_id) and run_id > 0,
       do: {:ok, run_id}

  defp link(execution_id, %IO.Tier{phase_run: %StudyPhaseRun{id: id}} = tier_io, gust_run_id) do
    phase_id = tier_io.phase.id

    case State.transaction(execution_id, &locked_link(&1, phase_id, id, gust_run_id)) do
      {:ok, %StudyPhaseRun{} = linked} -> {:ok, %{tier_io | phase_run: linked}}
      other -> other
    end
  end

  defp locked_link(%{state: :collecting_final}, phase_id, id, gust_run_id) do
    case lock_phase_run(id) do
      %StudyPhaseRun{study_phase_id: ^phase_id, gust_run_id: nil} = phase_run ->
        link_locked(phase_run, gust_run_id)

      %StudyPhaseRun{study_phase_id: ^phase_id, gust_run_id: ^gust_run_id} = phase_run ->
        link_locked(phase_run, gust_run_id)

      %StudyPhaseRun{} ->
        Repo.rollback({:error, StudyError.phase_run_conflict()})
    end
  end

  defp locked_link(%{state: state}, _phase_id, _id, _gust_run_id), do: State.stop(state)

  defp link_locked(%StudyPhaseRun{} = phase_run, gust_run_id) do
    case TierRuns.link_gust_run(phase_run, gust_run_id) do
      {:ok, %StudyPhaseRun{} = updated} -> {:ok, updated}
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp dispatch(execution_id, %IO.Tier{phase_run: %StudyPhaseRun{id: id} = phase_run}, workflow) do
    gust_run_id = phase_run.gust_run_id
    State.transaction(execution_id, &locked_dispatch(&1, id, gust_run_id, workflow))
  end

  defp locked_dispatch(%{state: :collecting_final}, id, gust_run_id, workflow) do
    case lock_phase_run(id) do
      %StudyPhaseRun{gust_run_id: ^gust_run_id} -> dispatch_locked(gust_run_id, workflow)
      %StudyPhaseRun{} -> Repo.rollback({:error, StudyError.phase_run_conflict()})
    end
  end

  defp locked_dispatch(%{state: state}, _id, _gust_run_id, _workflow), do: State.stop(state)

  defp dispatch_locked(gust_run_id, workflow) do
    case workflow.dispatch(gust_run_id) do
      :ok -> :ok
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
      _invalid -> Repo.rollback({:error, StudyError.final_collection_workflow_failed()})
    end
  end

  # The wait has no database lock. The stored state is authoritative afterwards,
  # so a cancellation that commits during the wait stops this tier.
  defp await(workflow, %IO.Tier{} = tier_io, timeout) do
    execution_id = tier_io.execution.id

    with {:ok, execution} <- ExecutionAccess.fetch(execution_id),
         {:ok, %StudyPhaseRun{} = phase_run} <- reload_phase_run(tier_io.phase_run),
         refreshed = %{tier_io | execution: execution, phase_run: phase_run},
         {:ok, timings} <- workflow.await(refreshed, timeout),
         :ok <- State.require_state(execution_id, :collecting_final) do
      {:ok, timings}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      {:stop, _state} = stop -> stop
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  end

  # The persisted complete-tier receipt must name this tier run before its
  # timings count as collected.
  defp receipt(workflow, %IO.Tier{} = tier_io) do
    with {:ok,
          %{"study_phase_run_id" => phase_run_id, "tier" => tier, "tier_position" => position}} <-
           workflow.result(tier_io.phase_run.gust_run_id),
         true <- phase_run_id == tier_io.phase_run.id,
         true <- tier == tier_io.tier,
         true <- position == tier_io.tier_position do
      :ok
    else
      false -> {:error, StudyError.incomplete_final_family()}
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.incomplete_final_family()}
    end
  end

  defp measured_positions(tier, timings) when is_list(timings) do
    positions = Enum.map(timings, & &1.position)

    if Enum.all?(timings, &match?(%ReplicaTiming{tier: ^tier}, &1)) and
         positions == Enum.to_list(0..4) do
      :ok
    else
      {:error, StudyError.final_timing_incomplete()}
    end
  end

  defp measured_positions(_tier, _timings), do: {:error, StudyError.final_timing_incomplete()}

  defp reload_phase_run(%StudyPhaseRun{id: id, gust_run_id: gust_run_id}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %StudyPhaseRun{gust_run_id: ^gust_run_id} = phase_run <-
           Repo.get(StudyPhaseRun, id) do
      {:ok, phase_run}
    else
      _invalid -> {:error, StudyError.phase_run_conflict()}
    end
  end

  defp lock_phase_run(phase_run_id) do
    Repo.one!(from run in StudyPhaseRun, where: run.id == ^phase_run_id, lock: "FOR UPDATE")
  end
end
