defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Boundary do
  @moduledoc false

  # Shared boundary of the Final analysis Gust tasks.
  #
  # Every task binds its work to the Gust run it executes. The stored run input
  # must decode as the Final analysis input, name the analysis phase run linked to
  # this run, and name the accepted Final snapshot of the same execution. The
  # binding proves ownership of the stored links; it does not re-derive the
  # accepted evidence or the declared comparisons.
  #
  # The mapped tasks carry one comparison job in, and one statistics value out.
  # Both are task-level transport of the analysis phase, so this module owns their
  # strict codecs next to the run binding. The statistics codec belongs to
  # `Final.AnalysisContract`, because the terminal family nests the same shape.
  #
  # Every tagged failure is logged through `Workflow.ActionBoundary` and raised
  # as one fixed permanent Gust message by the action. The tagged helpers return
  # the tagged result unchanged, so each action keeps the complete declared
  # result type of its capability.

  require Logger

  alias Gust.Flows
  alias Gust.Flows.Task
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Final.ComparisonJob
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Statistics
  alias NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary

  @evaluation_task "evaluate_final_comparison"
  @prepare_task "prepare_final_analysis"

  @context_failure "Evaluation2 Final analysis context is unavailable"
  @foreign_run_failure "Evaluation2 Final analysis task acted for another Gust run"
  @foreign_phase_failure "Evaluation2 Final analysis task acted for another phase"
  @foreign_snapshot_failure "Evaluation2 Final analysis snapshot belongs to another execution"
  @task_failure "Evaluation2 Final analysis task result is unavailable"
  @transport_failure "Evaluation2 Final analysis task result is invalid"

  # The task-level decoders compare the stored key count, so one canonical shape
  # per mapped value stays.

  @typedoc "Analysis phase run with its owning chain and the stored run input."
  @type run_context :: %{
          phase_run: PhaseRun.t(),
          phase: Persistence.Phase.t(),
          execution: Persistence.Execution.t(),
          revision: Persistence.Revision.t(),
          input: AnalysisContract.Input.t()
        }

  @doc """
  Bind a task to the phase run and the accepted snapshot of the acting run.

  The phase run must belong to the Final analysis phase, the acting Gust run must
  own the stored link, and the snapshot must belong to the Final collection phase
  of the same execution.
  """
  @spec run_context(map(), map()) :: {:ok, run_context()} | {:error, term()}
  def run_context(params, %{run_id: run_id}) do
    with {:ok, input} <- input(params),
         {:ok, context} <- analysis_context(input.phase_run_id, run_id),
         :ok <- expect_snapshot_owner(input.snapshot_id, context.execution) do
      {:ok, Map.put(context, :input, input)}
    end
  end

  @spec input(map()) :: {:ok, AnalysisContract.Input.t()} | {:error, :invalid_input}
  def input(params) do
    case AnalysisContract.decode_input(params) do
      {:ok, input} -> {:ok, input}
      :error -> tagged(:invalid_input, @context_failure)
    end
  end

  @spec phase_run_context(Ecto.UUID.t()) ::
          {:ok, Persistence.phase_run_context()} | {:error, term()}
  def phase_run_context(phase_run_id) do
    ActionBoundary.phase_run_context(@context_failure, phase_run_id)
  end

  @spec logged(String.t(), {:ok, value} | {:error, term()}) :: {:ok, value} | {:error, term()}
        when value: var
  def logged(message, result), do: ActionBoundary.logged(message, result)

  @doc "Log and return one tagged permanent failure."
  @spec tagged(term(), String.t()) :: {:error, term()}
  def tagged(cause, message) do
    Logger.error(message, cause: inspect(cause))
    {:error, cause}
  end

  # --- mapped job transport ----------------------------------------------

  @doc """
  Encode the prepared comparison batch as the mapped task parameters.

  The capability must return one usable job per declared comparison, so a foreign
  or empty batch never becomes a mapped stage.
  """
  @spec job_params(term()) ::
          {:ok, [%{required(String.t()) => non_neg_integer()}]} | {:error, term()}
  def job_params(jobs) when is_list(jobs) and jobs != [] do
    if Enum.all?(jobs, &prepared?/1) do
      {:ok, Enum.map(jobs, &job_to_params/1)}
    else
      tagged(:invalid_jobs, @transport_failure)
    end
  end

  def job_params(_jobs), do: tagged(:invalid_jobs, @transport_failure)

  defp prepared?(%ComparisonJob{comparison_position: position})
       when is_integer(position) and position >= 0,
       do: true

  defp prepared?(_job), do: false

  @doc "Encode one prepared comparison job as JSON-safe task parameters."
  @spec job_to_params(ComparisonJob.t()) :: %{required(String.t()) => non_neg_integer()}
  def job_to_params(%ComparisonJob{comparison_position: comparison_position}) do
    %{"comparison_position" => comparison_position}
  end

  @doc "Decode the mapped task parameters into one comparison job."
  @spec decode_job(term()) :: {:ok, ComparisonJob.t()} | :error
  def decode_job(%{"comparison_position" => comparison_position} = params)
      when is_integer(comparison_position) and comparison_position >= 0 and
             map_size(params) == 1 do
    {:ok, %ComparisonJob{comparison_position: comparison_position}}
  end

  def decode_job(_params), do: :error

  @spec run_job(term()) :: {:ok, ComparisonJob.t()} | {:error, :invalid_job}
  def run_job(params) do
    case decode_job(params) do
      {:ok, job} -> {:ok, job}
      :error -> tagged(:invalid_job, @transport_failure)
    end
  end

  # --- stored evaluation transport ---------------------------------------

  @doc """
  Encode one evaluated comparison as the stored mapped task result.

  The position comes from the prepared job, so one stored result belongs to one
  declared comparison.
  """
  @spec evaluation_params(ComparisonJob.t(), Statistics.t()) ::
          {:ok, %{required(String.t()) => term()}} | :error
  def evaluation_params(
        %ComparisonJob{comparison_position: comparison_position},
        %Statistics{} = statistics
      ) do
    with {:ok, statistics} <- AnalysisContract.encode_statistics(statistics) do
      {:ok, %{"comparison_position" => comparison_position, "statistics" => statistics}}
    end
  end

  def evaluation_params(_job, _statistics), do: :error

  @doc "Decode one stored mapped task result into its position and statistics."
  @spec decode_evaluation(term()) :: {:ok, {non_neg_integer(), Statistics.t()}} | :error
  def decode_evaluation(
        %{"comparison_position" => comparison_position, "statistics" => statistics} = params
      )
      when is_integer(comparison_position) and comparison_position >= 0 and
             map_size(params) == 2 do
    case AnalysisContract.decode_statistics(statistics) do
      {:ok, statistics} -> {:ok, {comparison_position, statistics}}
      :error -> :error
    end
  end

  def decode_evaluation(_params), do: :error

  @doc """
  Build the declared statistics batch from the stored mapped results.

  The batch must hold one usable result per declared position `0..n-1`, and the
  returned list follows that order. A gap, a repeat, or an unusable result
  rejects the whole batch, so a partial family never reaches correction.
  """
  @spec evaluations([term()]) :: {:ok, [Statistics.t()]} | {:error, :incomplete_evaluations}
  def evaluations(results) do
    case decode_all(results) do
      {:ok, pairs} -> completed(pairs)
      :error -> incomplete()
    end
  end

  @doc """
  Build the declared statistics batch of the acting run.

  The prepared job batch fixes the declared comparison positions, and the mapped
  stage must store exactly one succeeded evaluation per position. A missing,
  repeated, unfinished, or foreign evaluation never reaches correction.
  """
  @spec stored_statistics(pos_integer()) :: {:ok, [Statistics.t()]} | {:error, term()}
  def stored_statistics(run_id) do
    with {:ok, jobs} <- stored_jobs(run_id),
         {:ok, results} <- stored_evaluations(run_id),
         {:ok, statistics} <- evaluations(results),
         :ok <- expect_declared(jobs, results) do
      {:ok, statistics}
    end
  end

  @doc """
  Return the stored mapped results of the acting run.

  Every row of the mapped stage must be one succeeded task, because a fan-in
  over an unfinished or failed comparison would correct a partial family.
  """
  @spec stored_evaluations(pos_integer()) :: {:ok, [term()]} | {:error, term()}
  def stored_evaluations(run_id) do
    case Flows.get_tasks_by_name(@evaluation_task, run_id) do
      [_first | _rest] = tasks -> succeeded_results(tasks)
      _missing -> tagged(:missing_evaluations, @task_failure)
    end
  end

  @doc """
  Return the stored prepared job batch of the acting run.

  Gust stores the list result of the preparation task under the
  `gust_task_items` key, because the mapped stage expands one task per entry.
  """
  @spec stored_jobs(pos_integer()) :: {:ok, [ComparisonJob.t()]} | {:error, term()}
  def stored_jobs(run_id) do
    case Flows.get_tasks_by_name(@prepare_task, run_id) do
      [%Task{status: :succeeded, result: %{"gust_task_items" => items}}] -> decoded_jobs(items)
      _missing_or_repeated -> tagged(:missing_preparation, @task_failure)
    end
  end

  # --- ownership ---------------------------------------------------------

  # The acting task belongs to the analysis phase run linked to its Gust run.
  @spec analysis_context(Ecto.UUID.t(), term()) ::
          {:ok, Persistence.phase_run_context()} | {:error, term()}
  defp analysis_context(phase_run_id, run_id) do
    with {:ok, context} <- phase_run_context(phase_run_id),
         :ok <- expect_analysis_phase(context.phase) do
      case ActionBoundary.expect_run_id(context.phase_run, run_id, @foreign_run_failure) do
        :ok -> {:ok, context}
        {:error, _cause} = failure -> failure
      end
    end
  end

  @spec expect_analysis_phase(Persistence.Phase.t()) :: :ok | {:error, :foreign_phase}
  defp expect_analysis_phase(%{phase: :final_analysis}), do: :ok

  defp expect_analysis_phase(%{phase: phase}) do
    Logger.error(@foreign_phase_failure, phase: inspect(phase))
    {:error, :foreign_phase}
  end

  # The snapshot must belong to the Final collection phase of the same execution,
  # so an analysis run reads the evidence of its own study execution only.
  @spec expect_snapshot_owner(Ecto.UUID.t(), Persistence.Execution.t()) ::
          :ok | {:error, :foreign_snapshot}
  defp expect_snapshot_owner(snapshot_id, %{id: execution_id}) do
    with {:ok, context} <- snapshot_context(snapshot_id),
         :ok <- expect_final_collection(context.phase) do
      expect_same_execution(context.execution, execution_id)
    end
  end

  defp snapshot_context(snapshot_id) do
    case Persistence.fetch_evidence_context(snapshot_id) do
      {:ok, context} -> {:ok, context}
      {:error, cause} -> foreign_snapshot({:snapshot, cause})
    end
  end

  defp expect_final_collection(%{phase: :final_collection}), do: :ok

  defp expect_final_collection(%{phase: phase}), do: foreign_snapshot({:snapshot_phase, phase})

  # The rejection is logged with its detail, and the caller receives the one
  # stable cause of a foreign snapshot.
  defp foreign_snapshot(detail) do
    Logger.error(@foreign_snapshot_failure, cause: inspect(detail))
    {:error, :foreign_snapshot}
  end

  defp expect_same_execution(%{id: execution_id}, execution_id), do: :ok

  defp expect_same_execution(%{id: execution_id}, expected_execution_id) do
    foreign_snapshot({:execution, execution_id, expected_execution_id})
  end

  # --- batch internals ---------------------------------------------------

  @spec decode_all(term()) :: {:ok, [{non_neg_integer(), Statistics.t()}]} | :error
  defp decode_all(results) when is_list(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, decoded} ->
      case decode_evaluation(result) do
        {:ok, pair} -> {:cont, {:ok, [pair | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> decoded_pairs()
  end

  defp decode_all(_results), do: :error

  defp decoded_pairs({:ok, decoded}), do: {:ok, Enum.reverse(decoded)}
  defp decoded_pairs(:error), do: :error

  # A contiguous position set in ascending order is the declared comparison order
  # of the family.
  defp completed([_first | _rest] = pairs) do
    positions = pairs |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    if positions == Enum.to_list(0..(length(positions) - 1)//1) do
      {:ok, pairs |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}
    else
      incomplete()
    end
  end

  defp completed(_pairs), do: incomplete()

  defp incomplete, do: tagged(:incomplete_evaluations, @transport_failure)

  # Gust starts a mapped task again on retry and keeps one row per map index, so
  # every stored row of the mapped stage is one completed comparison.
  defp succeeded_results(tasks) do
    if Enum.all?(tasks, &match?(%Task{status: :succeeded}, &1)) do
      {:ok, Enum.map(tasks, & &1.result)}
    else
      tagged(:unfinished_evaluations, @task_failure)
    end
  end

  # One prepared batch per run, and every entry must decode as a comparison job.
  defp decoded_jobs(result) when is_list(result) and result != [] do
    decoded =
      Enum.reduce_while(result, {:ok, []}, fn params, {:ok, jobs} ->
        case decode_job(params) do
          {:ok, job} -> {:cont, {:ok, [job | jobs]}}
          :error -> {:halt, :error}
        end
      end)

    case decoded do
      {:ok, jobs} -> {:ok, Enum.reverse(jobs)}
      :error -> tagged(:invalid_preparation, @transport_failure)
    end
  end

  defp decoded_jobs(_result), do: tagged(:invalid_preparation, @transport_failure)

  # The stored evaluation positions must be exactly the prepared positions, so a
  # mapped row of another batch or a lost row stops the run.
  defp expect_declared(jobs, results) do
    declared = jobs |> Enum.map(& &1.comparison_position) |> Enum.sort()

    case stored_positions(results) do
      {:ok, positions} ->
        if positions == declared do
          :ok
        else
          tagged(:foreign_comparisons, @transport_failure)
        end

      :error ->
        tagged(:foreign_comparisons, @transport_failure)
    end
  end

  defp stored_positions(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, positions} ->
      case decode_evaluation(result) do
        {:ok, {position, _statistics}} -> {:cont, {:ok, [position | positions]}}
        :error -> {:halt, :error}
      end
    end)
    |> decoded_positions()
  end

  defp decoded_positions({:ok, positions}), do: {:ok, Enum.sort(positions)}
  defp decoded_positions(:error), do: :error
end
