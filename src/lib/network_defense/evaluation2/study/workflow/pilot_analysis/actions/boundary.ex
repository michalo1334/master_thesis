defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary do
  @moduledoc false

  # Shared boundary of the Pilot analysis Gust tasks.
  #
  # Every task binds its work to the Gust run it executes. The stored run input
  # must decode as the Pilot analysis input, name the analysis phase run linked to
  # this run, and name a Pilot collection snapshot of the same execution. The
  # binding proves ownership of the stored links; it does not re-derive the
  # accepted evidence or the planned work.
  #
  # The mapped tasks carry a job in, and the stored assessments travel out. Both
  # are task-level transport of the analysis phase, so this module owns their
  # strict codecs next to the run binding.
  #
  # Every tagged failure is logged through `Workflow.ActionBoundary` and raised
  # as one fixed permanent Gust message by the action. The tagged helpers return
  # the tagged result unchanged, so each action keeps the complete declared
  # result type of its capability.

  require Logger

  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Pilot.Assessment
  alias NetworkDefense.Evaluation2.Study.Pilot.Job
  alias NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary

  @context_failure "Evaluation2 Pilot analysis context is unavailable"
  @foreign_run_failure "Evaluation2 Pilot analysis task acted for another Gust run"
  @foreign_phase_failure "Evaluation2 Pilot analysis task acted for another phase"
  @foreign_snapshot_failure "Evaluation2 Pilot analysis snapshot belongs to another execution"

  @typedoc "Analysis phase run with its owning chain and the stored run input."
  @type run_context :: %{
          phase_run: PhaseRun.t(),
          phase: Persistence.Phase.t(),
          execution: Persistence.Execution.t(),
          revision: Persistence.Revision.t(),
          input: AnalysisContract.Input.t()
        }

  @spec run_context(map(), map()) :: {:ok, run_context()} | {:error, term()}
  def run_context(params, %{run_id: run_id}) do
    with {:ok, input} <- input(params),
         {:ok, context} <- phase_run_context(input.phase_run_id),
         :ok <- expect_analysis_phase(context.phase),
         :ok <- ActionBoundary.expect_run_id(context.phase_run, run_id, @foreign_run_failure),
         :ok <- expect_snapshot_owner(input.snapshot_id, context.execution) do
      {:ok, Map.put(context, :input, input)}
    end
  end

  @spec input(map()) :: {:ok, AnalysisContract.Input.t()} | {:error, :invalid_input}
  def input(params) do
    case AnalysisContract.decode_input(params) do
      {:ok, input} -> {:ok, input}
      :error -> {:error, :invalid_input}
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

  # --- mapped job transport ----------------------------------------------

  @spec job_to_params(Job.t()) :: map()
  def job_to_params(%Job{
        candidate_position: candidate_position,
        comparison_position: comparison_position,
        stream_seed: stream_seed
      }) do
    %{
      "candidate_position" => candidate_position,
      "comparison_position" => comparison_position,
      "stream_seed" => stream_seed
    }
  end

  @spec decode_job(term()) :: {:ok, Job.t()} | :error
  def decode_job(%{
        "candidate_position" => candidate_position,
        "comparison_position" => comparison_position,
        "stream_seed" => stream_seed
      })
      when is_integer(candidate_position) and candidate_position >= 0 and
             is_integer(comparison_position) and comparison_position >= 0 and
             is_integer(stream_seed) and stream_seed >= 0 do
    {:ok,
     %Job{
       candidate_position: candidate_position,
       comparison_position: comparison_position,
       stream_seed: stream_seed
     }}
  end

  def decode_job(_params), do: :error

  @spec run_job(term()) :: {:ok, Job.t()} | {:error, :invalid_job}
  def run_job(params) do
    case decode_job(params) do
      {:ok, job} -> {:ok, job}
      :error -> {:error, :invalid_job}
    end
  end

  # --- stored assessment transport ---------------------------------------

  @spec assessment_to_params(Assessment.t()) :: map()
  def assessment_to_params(%Assessment{
        candidate_position: candidate_position,
        comparison_position: comparison_position,
        guarded_half_width: guarded_half_width,
        informative: informative,
        passes: passes
      }) do
    %{
      "candidate_position" => candidate_position,
      "comparison_position" => comparison_position,
      "guarded_half_width" => guarded_half_width,
      "informative" => informative,
      "passes" => passes
    }
  end

  @spec decode_assessment(term()) :: {:ok, Assessment.t()} | :error
  def decode_assessment(%{
        "candidate_position" => candidate_position,
        "comparison_position" => comparison_position,
        "guarded_half_width" => guarded_half_width,
        "informative" => informative,
        "passes" => passes
      })
      when is_integer(candidate_position) and candidate_position >= 0 and
             is_integer(comparison_position) and comparison_position >= 0 and
             is_number(guarded_half_width) and is_boolean(informative) and is_boolean(passes) do
    {:ok,
     %Assessment{
       candidate_position: candidate_position,
       comparison_position: comparison_position,
       guarded_half_width: guarded_half_width * 1.0,
       informative: informative,
       passes: passes
     }}
  end

  def decode_assessment(_params), do: :error

  @spec assessments([term()]) :: {:ok, [Assessment.t()]} | {:error, :invalid_assessment}
  def assessments(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, decoded} ->
      case decode_assessment(result) do
        {:ok, assessment} -> {:cont, {:ok, [assessment | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> completed()
  end

  defp completed({:ok, decoded}), do: {:ok, Enum.reverse(decoded)}
  defp completed(:error), do: {:error, :invalid_assessment}

  # --- ownership ---------------------------------------------------------

  # The acting task belongs to the analysis phase run linked to its Gust run.
  @spec expect_analysis_phase(Persistence.Phase.t()) :: :ok | {:error, :foreign_phase}
  defp expect_analysis_phase(%{phase: :pilot_analysis}), do: :ok

  defp expect_analysis_phase(%{phase: phase}) do
    Logger.error(@foreign_phase_failure, phase: phase)
    {:error, :foreign_phase}
  end

  # The snapshot must belong to the Pilot collection phase of the same execution,
  # so an analysis run reads the evidence of its own study execution only.
  @spec expect_snapshot_owner(Ecto.UUID.t(), Persistence.Execution.t()) ::
          :ok | {:error, :foreign_snapshot}
  defp expect_snapshot_owner(snapshot_id, %{id: execution_id}) do
    with {:ok, context} <- snapshot_context(snapshot_id),
         :ok <- expect_pilot_collection(context.phase) do
      expect_same_execution(context.execution, execution_id)
    end
  end

  defp snapshot_context(snapshot_id) do
    case Persistence.fetch_evidence_context(snapshot_id) do
      {:ok, context} ->
        {:ok, context}

      {:error, cause} ->
        Logger.error(@foreign_snapshot_failure, cause: inspect(cause))
        {:error, :foreign_snapshot}
    end
  end

  defp expect_pilot_collection(%{phase: :pilot_collection}), do: :ok

  defp expect_pilot_collection(%{phase: phase}) do
    Logger.error(@foreign_snapshot_failure, phase: phase)
    {:error, :foreign_snapshot}
  end

  defp expect_same_execution(%{id: execution_id}, execution_id), do: :ok

  defp expect_same_execution(%{id: execution_id}, expected_execution_id) do
    Logger.error(@foreign_snapshot_failure,
      execution_id: execution_id,
      expected_execution_id: expected_execution_id
    )

    {:error, :foreign_snapshot}
  end
end
