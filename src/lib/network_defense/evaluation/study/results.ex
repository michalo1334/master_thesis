defmodule NetworkDefense.Evaluation.Study.Results do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Final.Contracts.Result, as: FinalResult

  alias NetworkDefense.Evaluation.Study.CompactResult
  alias NetworkDefense.Evaluation.Study.CompactResult.{AnalysisReference, CollectionReference}
  alias NetworkDefense.Evaluation.Study.CompactResult.PilotAnalysisReference
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{FinalSelection, Lifecycle, PilotOutcome, Revisions}

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyResult}
  alias NetworkDefense.Repo

  @phase_names [:pilot_collection, :pilot_analysis, :final_collection, :final_analysis]

  @spec create_success(StudyExecution.t(), FinalResult.t()) ::
          {:ok, CompactResult.t()} | {:stop, atom()} | {:error, StudyError.t()}
  def create_success(%StudyExecution{id: execution_id}, %FinalResult{} = final_result) do
    result =
      Repo.transaction(fn ->
        case lock_execution(execution_id) do
          %StudyExecution{state: :analyzing_final} = execution ->
            persist_success(execution, final_result)

          %StudyExecution{state: state} ->
            Repo.rollback({:stop, state})

          nil ->
            Repo.rollback({:error, StudyError.study_execution_not_found()})
        end
      end)

    transaction_result(result)
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_result_storage_failed()}
  end

  def create_success(_execution, _final_result),
    do: {:error, StudyError.final_result_invalid()}

  @spec get_for_execution(Ecto.UUID.t()) ::
          {:ok, CompactResult.t()} | {:error, StudyError.t()}
  def get_for_execution(execution_id) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{state: :succeeded} = execution <- Repo.get(StudyExecution, id),
         %StudyResult{} = row <- Repo.get_by(StudyResult, execution_id: id),
         {:ok, compact} <- CompactResult.parse(row.data),
         :ok <- validate_readback(execution, row, compact) do
      {:ok, compact}
    else
      _unavailable -> {:error, StudyError.result_unavailable()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.result_unavailable()}
  end

  defp persist_success(%StudyExecution{} = execution, %FinalResult{} = final_result) do
    with {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, selection} <- FinalSelection.from_execution(execution),
         {:ok, outcome} <- parse_outcome(execution.pilot_outcome),
         {:ok, phases} <- lock_phases(execution),
         :ok <- validate_phases(execution, phases),
         :ok <- validate_final_result(execution, selection, definition, phases, final_result),
         {:ok, compact} <-
           compact_result(execution, selection, outcome, definition, phases, final_result),
         {:ok, row} <- insert_result(execution, compact),
         {:ok, _phase} <- store_result_reference(phases.final_analysis, row.id),
         {:ok, _execution} <- succeed(execution) do
      {:ok, compact}
    else
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
      _invalid -> Repo.rollback({:error, StudyError.final_result_storage_failed()})
    end
  end

  defp lock_execution(execution_id) do
    Repo.one(
      from execution in StudyExecution,
        where: execution.id == ^execution_id,
        lock: "FOR UPDATE"
    )
  end

  defp lock_phases(%StudyExecution{} = execution) do
    phases =
      Repo.all(
        from phase in StudyPhase,
          where: phase.execution_id == ^execution.id and phase.phase in ^@phase_names,
          order_by: phase.phase,
          lock: "FOR UPDATE"
      )

    by_name = Map.new(phases, &{&1.phase, &1})

    if Map.keys(by_name) |> Enum.sort() == Enum.sort(@phase_names) do
      {:ok,
       %{
         pilot_collection: by_name.pilot_collection,
         pilot_analysis: by_name.pilot_analysis,
         final_collection: by_name.final_collection,
         final_analysis: by_name.final_analysis
       }}
    else
      {:error, StudyError.final_result_invalid()}
    end
  end

  defp validate_phases(execution, phases) do
    valid? =
      complete_collection?(phases.pilot_collection) and
        complete_pilot_analysis?(phases.pilot_analysis, execution.pilot_outcome) and
        complete_collection?(phases.final_collection) and
        empty_final_analysis?(phases.final_analysis)

    if valid?, do: :ok, else: {:error, StudyError.final_result_invalid()}
  end

  defp complete_collection?(%StudyPhase{} = phase) do
    positive_run?(phase.gust_run_id) and uuid?(phase.snapshot_id) and is_nil(phase.error)
  end

  defp complete_pilot_analysis?(%StudyPhase{} = phase, outcome) do
    positive_run?(phase.gust_run_id) and phase.result_ref == outcome and is_nil(phase.error)
  end

  defp empty_final_analysis?(%StudyPhase{} = phase) do
    positive_run?(phase.gust_run_id) and is_nil(phase.result_ref) and is_nil(phase.error)
  end

  defp validate_final_result(execution, selection, definition, phases, final_result) do
    comparisons = Enum.map(definition.family.comparisons, &comparison_key/1)
    result_comparisons = Enum.map(final_result.comparisons, &comparison_key(&1.identity))

    checks = [
      final_result.study_revision_id == execution.study_revision_id,
      final_result.snapshot_id == phases.final_collection.snapshot_id,
      final_result.source_pilot_run_id == phases.pilot_analysis.gust_run_id,
      final_result.plan_count == selection.plan_count_per_side,
      final_result.attacks_per_plan == selection.attacks_per_plan,
      final_result.family_id == definition.family.id,
      final_result.method == definition.family.method,
      final_result.alpha == definition.family.alpha,
      final_result.family_size == length(comparisons),
      result_comparisons == comparisons,
      completion_assertions?(final_result, phases.final_collection)
    ]

    if Enum.all?(checks), do: :ok, else: {:error, StudyError.final_result_invalid()}
  end

  defp completion_assertions?(final_result, final_collection) do
    assertions = final_result.assertions

    assertions.final_evidence_collected_after_pilot == true and
      assertions.pilot_observations_excluded == true and
      assertions.collection_completed_at == DateTime.to_iso8601(final_collection.updated_at)
  end

  defp comparison_key(comparison) do
    {
      comparison.tier,
      comparison.budget,
      strategy_name(comparison.alternative),
      strategy_name(comparison.reference),
      comparison.outcome
    }
  end

  defp strategy_name(value) when is_atom(value), do: Atom.to_string(value)
  defp strategy_name(value) when is_binary(value), do: value

  defp compact_result(execution, selection, outcome, definition, phases, final_result) do
    compact = %CompactResult{
      study_revision_id: execution.study_revision_id,
      execution_id: execution.id,
      pilot_collection: collection_reference(phases.pilot_collection),
      pilot_analysis: %PilotAnalysisReference{
        phase_id: phases.pilot_analysis.id,
        gust_run_id: phases.pilot_analysis.gust_run_id,
        outcome: outcome
      },
      selection: selection,
      final_collection: collection_reference(phases.final_collection),
      final_analysis: %AnalysisReference{
        phase_id: phases.final_analysis.id,
        gust_run_id: phases.final_analysis.gust_run_id
      },
      final_result: final_result,
      revision_assertions: definition.study.revisions,
      timing: nil
    }

    compact |> CompactResult.to_params() |> CompactResult.parse()
  end

  defp collection_reference(phase) do
    %CollectionReference{
      phase_id: phase.id,
      gust_run_id: phase.gust_run_id,
      snapshot_id: phase.snapshot_id
    }
  end

  defp insert_result(execution, compact) do
    %StudyResult{}
    |> StudyResult.create_changeset(%{
      execution_id: execution.id,
      schema_version: 1,
      data: CompactResult.to_params(compact)
    })
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, _changeset} -> {:error, StudyError.final_result_storage_failed()}
    end
  end

  defp store_result_reference(phase, result_id) do
    phase
    |> StudyPhase.changeset(%{result_ref: %{"study_result_id" => result_id}})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, _changeset} -> {:error, StudyError.final_result_storage_failed()}
    end
  end

  defp succeed(execution) do
    case Lifecycle.transition(execution.state, :final_analyzed) do
      {:ok, :succeeded} ->
        execution
        |> StudyExecution.changeset(%{state: :succeeded})
        |> Repo.update()

      _invalid ->
        {:error, StudyError.final_result_storage_failed()}
    end
  end

  defp parse_outcome(params) do
    case PilotOutcome.parse(params) do
      {:ok, outcome} -> {:ok, outcome}
      {:error, _error} -> {:error, StudyError.final_result_invalid()}
    end
  end

  defp validate_readback(execution, row, compact) do
    with {:ok, selection} <- FinalSelection.from_execution(execution),
         {:ok, outcome} <- parse_outcome(execution.pilot_outcome),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, phases} <- read_phases(execution),
         true <- row.schema_version == 1,
         true <- compact.execution_id == execution.id,
         true <- compact.study_revision_id == execution.study_revision_id,
         true <- compact.selection == selection,
         true <- compact.pilot_analysis.outcome == outcome,
         true <- compact.revision_assertions == definition.study.revisions,
         true <- readback_phases_match?(compact, phases, row.id),
         :ok <-
           validate_final_result(
             execution,
             selection,
             definition,
             phases,
             compact.final_result
           ) do
      :ok
    else
      _invalid -> {:error, StudyError.result_unavailable()}
    end
  end

  defp read_phases(execution) do
    phases = Repo.all(from phase in StudyPhase, where: phase.execution_id == ^execution.id)
    by_name = Map.new(phases, &{&1.phase, &1})

    if Map.keys(by_name) |> Enum.sort() == Enum.sort(@phase_names) do
      {:ok,
       %{
         pilot_collection: by_name.pilot_collection,
         pilot_analysis: by_name.pilot_analysis,
         final_collection: by_name.final_collection,
         final_analysis: by_name.final_analysis
       }}
    else
      {:error, StudyError.result_unavailable()}
    end
  end

  defp readback_phases_match?(compact, phases, result_id) do
    checks = [
      complete_collection?(phases.pilot_collection),
      complete_pilot_analysis?(
        phases.pilot_analysis,
        PilotOutcome.to_params(compact.pilot_analysis.outcome)
      ),
      complete_collection?(phases.final_collection),
      positive_run?(phases.final_analysis.gust_run_id),
      is_nil(phases.final_analysis.error),
      phases.final_analysis.result_ref == %{"study_result_id" => result_id},
      collection_matches?(compact.pilot_collection, phases.pilot_collection),
      compact.pilot_analysis.phase_id == phases.pilot_analysis.id,
      compact.pilot_analysis.gust_run_id == phases.pilot_analysis.gust_run_id,
      collection_matches?(compact.final_collection, phases.final_collection),
      compact.final_analysis.phase_id == phases.final_analysis.id,
      compact.final_analysis.gust_run_id == phases.final_analysis.gust_run_id
    ]

    Enum.all?(checks)
  end

  defp collection_matches?(reference, phase) do
    reference.phase_id == phase.id and reference.gust_run_id == phase.gust_run_id and
      reference.snapshot_id == phase.snapshot_id
  end

  defp transaction_result({:ok, {:ok, compact}}), do: {:ok, compact}
  defp transaction_result({:error, {:stop, state}}), do: {:stop, state}
  defp transaction_result({:error, {:error, %StudyError{} = error}}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.final_result_storage_failed()}

  defp positive_run?(value), do: is_integer(value) and value > 0
  defp uuid?(value), do: match?({:ok, _id}, Ecto.UUID.cast(value))
end
