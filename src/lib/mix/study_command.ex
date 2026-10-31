defmodule Mix.Study.Command do
  @moduledoc """
  Shared startup policy and operator-facing output of the `mix study.*` commands.

  The commands are thin clients of `NetworkDefense.Evaluation2.Study`. This module
  owns the parts that stay outside that boundary: application startup, command
  failure, and printed output. It reads no stored row and owns no lifecycle
  transition, timing, or science.

  ## Startup policy

  Execution mode (`:execute`) suits a command that drives a study to a new
  boundary. It needs Gust workers, keeps a declared execution-capable Gust role,
  and rejects a role that dispatches no DAG runs, because such a command would
  wait for work that nobody claims.

  Inspection mode (`:inspect`) always uses the non-executing Gust `console` role.
  A read command uses it, so queued work of another study stays unclaimed by that
  command VM. A cancellation command also uses it: the durable cancel is the
  decision, and claiming queued work before that commit would start the very work
  the operator cancels.
  """

  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result, as: StudyResult
  alias NetworkDefense.Evaluation2.Study.Result.Comparison, as: ResultComparison
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.Study.Tier

  @typedoc "Startup intent of one command."
  @type mode :: :execute | :inspect

  @execution_role "core"
  @inspection_role "console"
  @non_dispatching_roles ["console", "web"]

  @doc """
  Start the normal application for one command mode.

  Execution mode keeps a declared execution-capable role and uses `core`
  otherwise. Inspection mode always uses `console`. A start failure becomes a
  command error, so a command never continues without its runtime.
  """
  @spec start!(mode(), (atom() -> {:ok, [atom()]} | {:error, term()})) :: :ok
  def start!(mode, start_application \\ &Application.ensure_all_started/1)

  def start!(:execute, start_application) do
    case System.get_env("GUST_ROLE") || @execution_role do
      role when role in @non_dispatching_roles -> Mix.raise(role_error(role))
      role -> start_role(role, start_application)
    end
  end

  def start!(:inspect, start_application) do
    start_role(@inspection_role, start_application)
  end

  defp start_role(role, start_application) do
    System.put_env("GUST_ROLE", role)

    case start_application.(:network_defense) do
      {:ok, _applications} -> :ok
      {:error, reason} -> Mix.raise("Cannot start the application: #{inspect(reason)}")
    end
  end

  defp role_error(role) do
    "GUST_ROLE=#{role} starts Gust without DAG dispatch, so a study cannot run. " <>
      "Use GUST_ROLE=#{@execution_role} or leave GUST_ROLE unset."
  end

  @doc "Print one block of output lines."
  @spec print([String.t()]) :: :ok
  def print(lines), do: Enum.each(lines, fn line -> Mix.shell().info(line) end)

  @doc """
  Report one supported study failure and stop the command.

  The bounded issues reach the operator. The raised error names the operation.
  """
  @spec reject!(atom(), Error.t()) :: no_return()
  def reject!(operation, %Error{} = error) do
    Mix.shell().error(Enum.join(issue_lines(error), "\n"))
    Mix.raise("study #{operation} failed")
  end

  @doc "Report one command-level failure and stop the command."
  @spec fail!(atom(), String.t()) :: no_return()
  def fail!(operation, detail) do
    Mix.shell().error(detail)
    Mix.raise("study #{operation} failed")
  end

  @doc """
  Stop the command unless the status reached an expected boundary.

  An unexpected state means the requested step did not reach its operator or
  terminal boundary, so the command must not report success.
  """
  @spec require_boundary!(atom(), Status.t(), [atom()]) :: :ok
  def require_boundary!(operation, %Status{state: state}, allowed) do
    if state in allowed do
      :ok
    else
      fail!(operation, "The execution stopped at #{state}.")
    end
  end

  @doc "Build the printed block of one lifecycle status."
  @spec status_lines(Status.t()) :: [String.t()]
  def status_lines(%Status{} = status) do
    [
      "Execution: #{status.execution_id}",
      "Study: #{status.revision.study_id}",
      "Revision: #{status.revision.revision}",
      "State: #{status.state}"
    ] ++
      outcome_lines(status.pilot_outcome) ++
      selection_lines(status.selection) ++ error_lines(status.error)
  end

  @doc "Build the printed block of one complete Pilot report."
  @spec pilot_report_lines(PilotResult.t()) :: [String.t()]
  def pilot_report_lines(%PilotResult{} = report) do
    [
      "",
      "Pilot report",
      "Method: #{report.method}",
      "Selection rule: #{report.selection_rule}"
    ] ++
      outcome_lines(report.outcome) ++
      Enum.flat_map(report.candidates, &candidate_lines/1)
  end

  @doc "Build the printed block of one successful study result."
  @spec result_lines(StudyResult.t()) :: [String.t()]
  def result_lines(%StudyResult{} = result) do
    [
      "",
      "Result",
      "Execution: #{result.execution_id}",
      "Study: #{result.revision.study_id}",
      "Revision: #{result.revision.revision}",
      "Family: #{result.family.id}",
      "Method: #{result.family.method}",
      "Alpha: #{format_number(result.family.alpha)}"
    ] ++
      Enum.flat_map(result.family.comparisons, &result_comparison_lines/1) ++
      timing_lines(result.timing)
  end

  defp outcome_lines(nil), do: []

  defp outcome_lines(%PilotOutcome{outcome: :recommended} = outcome) do
    ["Pilot outcome: recommended " <> sample_text(outcome)]
  end

  defp outcome_lines(%PilotOutcome{outcome: :insufficient}), do: ["Pilot outcome: insufficient"]

  defp selection_lines(nil), do: []
  defp selection_lines(%Selection{} = selection), do: ["Selection: " <> sample_text(selection)]

  defp sample_text(sample) do
    "candidate #{sample.candidate_id}, #{sample.plan_count_per_side} plans per side, " <>
      "#{sample.attacks_per_plan} attacks per plan"
  end

  defp error_lines(nil), do: []
  defp error_lines(%Error{} = error), do: Enum.map(issue_lines(error), &("Error: " <> &1))

  defp issue_lines(%Error{} = error) do
    Enum.map(error.issues, &issue_line/1)
  end

  defp issue_line(%Error.Issue{} = issue) do
    "#{issue.code}#{path_text(issue.path)}: #{issue.message}"
  end

  defp path_text([]), do: ""
  defp path_text(path), do: " at " <> Enum.map_join(path, ".", &to_string/1)

  defp candidate_lines(assessment) do
    comparisons = Enum.map(assessment.comparisons, &pilot_assessment_line/1)

    [
      "Candidate #{assessment.id}: #{assessment.plan_count_per_side} plans per side, " <>
        "#{assessment.attacks_per_plan} attacks per plan, predicted runtime " <>
        "#{format_number(assessment.predicted_runtime_ms)} ms, worst guarded half-width " <>
        "#{format_number(PilotResult.Candidate.worst_guarded_half_width(assessment))}, " <>
        "passes: #{PilotResult.Candidate.passes?(assessment)}"
      | comparisons
    ]
  end

  defp pilot_assessment_line(%PilotResult.Comparison{} = comparison) do
    "  " <>
      identity_text(comparison.identity) <>
      ": guarded half-width #{format_number(comparison.guarded_half_width)}, " <>
      "informative: #{comparison.informative}, passes: #{comparison.passes}"
  end

  defp result_comparison_lines(%ResultComparison{} = comparison) do
    statistics = comparison.statistics
    interval = statistics.interval
    assessment = statistics.assessment

    [
      "Comparison " <> identity_text(comparison.identity),
      "  estimate #{format_number(statistics.estimate.value)}, interval " <>
        "[#{format_number(interval.lower)}, #{format_number(interval.upper)}] " <>
        "at #{format_number(interval.confidence_level)}",
      "  raw p-value #{format_number(statistics.test.raw_p_value)}, " <>
        "adjusted p-value #{format_number(comparison.adjustment.adjusted_p_value)}, " <>
        "reject null: #{comparison.adjustment.reject_null}",
      "  assessment: #{assessment.status}, warnings: #{warning_text(assessment.warnings)}"
    ]
  end

  defp identity_text(identity) do
    "#{identity.tier} budget #{identity.budget} " <>
      "#{identity.alternative} vs #{identity.reference} #{identity.outcome}"
  end

  defp warning_text([]), do: "none"
  defp warning_text(warnings), do: Enum.map_join(warnings, ", ", &to_string/1)

  defp timing_lines(%Timing{} = timing) do
    ["", "Timing (median of five measured replicas)"] ++
      Enum.map(Tier.all(), fn tier -> timing_line(timing, tier) end)
  end

  defp timing_line(timing, tier) do
    {minimum, maximum} = Timing.range(timing, tier, :total)

    "#{tier}: plan selection #{Timing.median(timing, tier, :plan_selection)} us, " <>
      "simulation #{Timing.median(timing, tier, :simulation)} us, " <>
      "total #{Timing.median(timing, tier, :total)} us " <>
      "(total range #{minimum}-#{maximum} us)"
  end

  defp format_number(value) when is_integer(value), do: Integer.to_string(value)
  defp format_number(value) when is_float(value), do: Float.to_string(value)
end
