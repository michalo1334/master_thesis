defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc """
  Gust coordination of the study phases.

  Each typed contract binds one phase to its own input and output. Shared Gust
  mechanics stay private.

  ## Pilot Collection provisioning

  The caller supplies the phase-run identity before the Gust run exists, and the
  same identity travels inside the run input. The canonical phase-run link
  decides which Gust run may run. Dispatch is conditional on the authoritative
  Gust status, so a stale caller cannot enqueue a run twice.

  ```mermaid
  sequenceDiagram
      participant C as Caller
      participant W as Study.Workflow
      participant P as Study.Persistence
      participant G as Gust

      C->>W: ensure_pilot_collection_run(phase_id)
      W->>P: fetch_phase_run(phase_id, :single)
      alt phase run linked
          P-->>W: canonical phase run
      else no link yet
          W->>W: generate the phase-run UUID
          W->>G: create an undispatched run with that UUID
          W->>P: link_phase_run(phase_id, :single, UUID, run id)
          P-->>W: canonical phase run
          Note over W,G: a losing caller deletes its own run first
      end
      W->>G: dispatch under the Gust run row lock
      G-->>W: enqueued run, or unchanged created run
      W-->>C: canonical phase run, or one bounded error
  ```

  A crash between run creation and the phase-run link leaves an inert `:created`
  Gust run. It performs no study work, and this module removes no such row.

  ## Completion

  Gust success alone does not prove a completed phase: the stored run input, the
  run status, the declared terminal task, and the stored terminal result must
  agree with the canonical phase run.
  """

  import Ecto.Query

  require Logger

  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.Flows.Run
  alias Gust.Flows.Task
  alias Gust.Repo, as: GustRepo
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.{Error, Final, Persistence, Pilot}
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Views

  # The DAG name is the checked-in file name of the DAG source, and the terminal
  # task is the last task of that DAG.
  @pilot_collection_dag "evaluation2_study_pilot_collection"
  @pilot_collection_terminal_task "complete_pilot_collection"
  @loser_cleanup_failure "Evaluation2 Pilot collection removed no losing Gust run"

  @type pilot_result :: {:paused, Persistence.Execution.t()} | {:error, Error.t()}
  @type final_result :: {:completed, Persistence.Result.t()} | {:error, Error.t()}

  @spec run_pilot(Persistence.Execution.t()) :: pilot_result()
  def run_pilot(_execution), do: raise(NotImplementedError, function: :run_pilot)

  @spec run_final(Persistence.Execution.t()) :: final_result()
  def run_final(_execution), do: raise(NotImplementedError, function: :run_final)

  @spec run_pilot_collection(Pilot.CollectionContract.Input.t()) ::
          {:ok, Pilot.CollectionContract.Output.t()} | {:error, Error.t()}
  def run_pilot_collection(input) do
    dispatch(Pilot.CollectionContract, input, :assemble_pilot_snapshot)
    |> decode_result(&Pilot.CollectionContract.decode_output!/1)
  end

  @spec run_pilot_analysis(Pilot.AnalysisContract.Input.t()) ::
          {:ok, Pilot.AnalysisContract.Output.t()} | {:error, Error.t()}
  def run_pilot_analysis(input) do
    dispatch(Pilot.AnalysisContract, input, :select_pilot_outcome)
    |> decode_result(&Pilot.AnalysisContract.decode_output!/1)
  end

  @spec run_final_tier(Final.TierContract.Input.t()) ::
          {:ok, Final.TierContract.Output.t()} | {:error, Error.t()}
  def run_final_tier(input) do
    dispatch(Final.TierContract, input, :complete_final_tier)
    |> decode_result(&Final.TierContract.decode_output!/1)
  end

  @spec run_final_analysis(Final.AnalysisContract.Input.t()) ::
          {:ok, Final.AnalysisContract.Output.t()} | {:error, Error.t()}
  def run_final_analysis(input) do
    dispatch(Final.AnalysisContract, input, :correct_final_family)
    |> decode_result(&Final.AnalysisContract.decode_output!/1)
  end

  @spec dispatch(module(), map(), atom()) :: {:ok, map()} | {:error, Error.t()}
  defp dispatch(_contract, _input, _terminal), do: {:error, Placeholder.error(:dispatch)}

  # The scaffold dispatcher returns only errors until Gust execution is
  # implemented, so the success branch stays unreachable until then.
  @dialyzer {:nowarn_function, decode_result: 2}
  @spec decode_result({:ok, map()} | {:error, Error.t()}, (map() -> result)) ::
          {:ok, result} | {:error, Error.t()}
        when result: var
  defp decode_result(result, decoder) do
    case result do
      {:ok, raw} -> {:ok, decoder.(raw)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Ensure the dispatched Pilot Collection run of one collection phase.

  A linked phase run is reused, so a repeated call or a restart converges on the
  same Gust run. A missing link creates the phase-run identity, the undispatched
  Gust run, and the canonical link in that order.

  A caller that loses the link race deletes its own run first and then dispatches
  the canonical run. A run that is already active or terminal returns unchanged.
  """
  @spec ensure_pilot_collection_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, Error.t()}
  def ensure_pilot_collection_run(phase_id) do
    case Persistence.fetch_phase_run(phase_id, :single) do
      {:ok, phase_run} ->
        dispatch_linked_run(phase_run)

      {:error, %Persistence.Error{kind: :not_found}} ->
        create_linked_run(phase_id)

      {:error, failure} ->
        {:error, Views.error(failure)}
    end
  end

  @doc """
  Read the completion of one Pilot Collection phase run.

  The operation loads the canonical phase run of that identifier, then requires
  the linked Gust run to name the same phase run in its stored input, to have
  succeeded, and to own exactly one succeeded terminal task whose stored result
  decodes as the empty Pilot Collection output.
  """
  @spec pilot_collection_result(Ecto.UUID.t()) ::
          {:ok, Pilot.CollectionContract.Output.t()} | {:error, Error.t()}
  def pilot_collection_result(phase_run_id) do
    with {:ok, phase_run} <- canonical_phase_run(phase_run_id),
         {:ok, run} <- fetch_run(phase_run.gust_run_id),
         {:ok, input} <- decode_run_input(run),
         :ok <- expect_phase_run(input, phase_run),
         :ok <- expect_run_status(run),
         {:ok, terminal} <- fetch_terminal_task(run.id),
         :ok <- expect_task_status(terminal) do
      decode_terminal_result(terminal)
    end
  end

  defp create_linked_run(phase_id) do
    phase_run_id = Ecto.UUID.generate()
    input = %Pilot.CollectionContract.Input{phase_run_id: phase_run_id}

    with {:ok, dag_id} <- pilot_collection_dag_id(),
         {:ok, run} <- create_run(dag_id, Pilot.CollectionContract.to_params(input)),
         {:ok, canonical} <- link_run(phase_id, phase_run_id, run.id) do
      settle_created_run(run, canonical)
    end
  end

  defp pilot_collection_dag_id do
    case contained(fn -> Flows.get_dag_by_name(@pilot_collection_dag) end) do
      %Flows.Dag{id: dag_id} -> {:ok, dag_id}
      nil -> {:error, unavailable()}
      {:error, failure} -> {:error, failure}
    end
  end

  defp create_run(dag_id, params) do
    case contained(fn -> Flows.create_run(%{dag_id: dag_id, params: params}) end) do
      {:ok, %Run{} = run} -> {:ok, run}
      {:error, %Error{} = failure} -> {:error, failure}
      {:error, _changeset} -> {:error, unavailable()}
    end
  end

  defp link_run(phase_id, phase_run_id, gust_run_id) do
    case Persistence.link_phase_run(phase_id, :single, phase_run_id, gust_run_id) do
      {:ok, phase_run} -> {:ok, phase_run}
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  # The canonical row names the winner. A losing caller removes its own
  # undispatched run first, then the canonical run is dispatched either way.
  defp settle_created_run(%Run{id: run_id}, %PhaseRun{gust_run_id: run_id} = phase_run) do
    with {:ok, _run} <- dispatch_run(run_id) do
      {:ok, phase_run}
    end
  end

  defp settle_created_run(%Run{} = created_run, %PhaseRun{} = canonical) do
    discard_run(created_run)

    with {:ok, _run} <- dispatch_run(canonical.gust_run_id) do
      {:ok, canonical}
    end
  end

  # Cleanup is best effort: the row was never dispatched, so a failed delete
  # leaves no active work and the canonical dispatch continues.
  defp discard_run(%Run{id: run_id} = run) do
    case contained(fn -> GustRepo.delete(run) end) do
      {:ok, _deleted} -> :ok
      _not_deleted -> Logger.warning(@loser_cleanup_failure, run_id: run_id)
    end
  end

  defp dispatch_linked_run(%PhaseRun{gust_run_id: run_id} = phase_run) do
    with {:ok, _run} <- dispatch_run(run_id) do
      {:ok, phase_run}
    end
  end

  # Gust enqueue does not check the current status, so the authoritative status is
  # read under the Gust run row lock. A run that is no longer created stays
  # untouched, and a disabled DAG leaves the run created and unavailable.
  defp dispatch_run(run_id) do
    run_id
    |> locked_dispatch()
    |> dispatched()
  end

  defp locked_dispatch(run_id) do
    contained(fn -> locked_transaction(run_id) end)
  end

  defp locked_transaction(run_id) do
    GustRepo.transaction(fn -> locked_run(run_id) end)
  end

  defp locked_run(run_id) do
    case GustRepo.one(from run in Run, where: run.id == ^run_id, lock: "FOR UPDATE") do
      nil -> GustRepo.rollback(:missing_run)
      %Run{status: :created} = run -> Trigger.dispatch_run(run)
      %Run{} = run -> run
    end
  end

  defp dispatched({:error, %Error{} = failure}), do: {:error, failure}
  defp dispatched({:ok, %Run{status: :created}}), do: {:error, unavailable()}
  defp dispatched({:ok, %Run{} = run}), do: {:ok, run}
  defp dispatched({:error, _reason}), do: {:error, unavailable()}

  defp canonical_phase_run(phase_run_id) do
    case Persistence.fetch_phase_run_context(phase_run_id) do
      {:ok, context} -> {:ok, context.phase_run}
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  defp fetch_run(run_id) do
    case contained(fn -> GustRepo.get(Run, run_id) end) do
      %Run{} = run -> {:ok, run}
      nil -> {:error, incomplete()}
      {:error, failure} -> {:error, failure}
    end
  end

  defp decode_run_input(%Run{params: params}) do
    case Pilot.CollectionContract.decode_input(params) do
      {:ok, input} -> {:ok, input}
      :error -> {:error, incomplete()}
    end
  end

  defp expect_phase_run(%Pilot.CollectionContract.Input{phase_run_id: id}, %PhaseRun{id: id}),
    do: :ok

  defp expect_phase_run(_input, _phase_run), do: {:error, incomplete()}

  defp expect_run_status(%Run{status: :succeeded}), do: :ok
  defp expect_run_status(%Run{}), do: {:error, incomplete()}

  defp fetch_terminal_task(run_id) do
    case contained(fn -> Flows.get_tasks_by_name(@pilot_collection_terminal_task, run_id) end) do
      [%Task{} = task] -> {:ok, task}
      {:error, %Error{} = failure} -> {:error, failure}
      _missing_or_duplicated -> {:error, incomplete()}
    end
  end

  defp expect_task_status(%Task{status: :succeeded}), do: :ok
  defp expect_task_status(%Task{}), do: {:error, incomplete()}

  defp decode_terminal_result(%Task{result: result}) do
    case Pilot.CollectionContract.decode_output(result) do
      {:ok, output} -> {:ok, output}
      :error -> {:error, incomplete()}
    end
  end

  # Gust, PostgreSQL, and connection failures are expected operational outcomes of
  # the Gust store, so they become the bounded collection error. Every other
  # exception stays a programming error and raises.
  @spec contained((-> result)) :: result | {:error, Error.t()} when result: var
  defp contained(fun) do
    fun.()
  rescue
    exception in [Postgrex.Error, DBConnection.ConnectionError, DBConnection.OwnershipError] ->
      Logger.error("Evaluation2 Pilot collection Gust storage failed",
        error: Exception.message(exception)
      )

      {:error, unavailable()}
  end

  # Both failures stay bounded: the internal Gust run, task, and status detail
  # never crosses this boundary.
  defp unavailable do
    bounded_error("collection_unavailable", "The Pilot collection run is unavailable.")
  end

  defp incomplete do
    bounded_error("collection_incomplete", "The Pilot collection run has not completed.")
  end

  defp bounded_error(code, message) do
    %Error{
      category: :unavailable,
      issues: [%Error.Issue{code: code, path: [], message: message}]
    }
  end
end
