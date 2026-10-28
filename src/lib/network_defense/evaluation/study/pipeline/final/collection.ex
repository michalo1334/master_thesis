defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO, as: AnalysisIO

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.{
    Acceptance,
    IO,
    ReplicaFamily,
    Snapshot,
    Tiers,
    Workflow
  }

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.TimingSummary
  alias NetworkDefense.Evaluation.Study.Pipeline.State

  # The Final collection stage.
  #
  # The stage runs synchronously in the coordinator process, so the coordinator
  # stays the timing-marker owner and receives the same messages as before.
  #
  # Flow: every declared tier, one at a time; the timing family; a state recheck;
  # the measured replica family; the replica-zero snapshot; the acceptance
  # transition. The result is the accepted handoff to Final analysis.
  #
  # Timings live in memory only. They cross no task boundary and no table.
  #
  # Options:
  #
  #   * `:workflow` — the tier workflow module. The default creates one Gust run
  #     per tier.
  #   * `:snapshot` — the snapshot module. The default assembles and stores the
  #     replica-zero evidence snapshot.
  #   * `:timeout` — the per-tier await timeout. The default is `:infinity`.
  @defaults [workflow: Workflow, snapshot: Snapshot, timeout: :infinity]

  @spec run(IO.t(), keyword()) ::
          {:ok, AnalysisIO.t()} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{tiers: tiers} = io, opts \\ []) do
    options = Keyword.merge(@defaults, opts)

    with {:ok, family} <- Tiers.run(io, Keyword.take(options, [:workflow, :timeout])),
         {:ok, timing_summary} <- TimingSummary.summarize(tiers, family),
         :ok <- State.require_state(io.execution.id, :collecting_final),
         {:ok, items} <- ReplicaFamily.run(io.phase, io.definition),
         {:ok, snapshot_id} <-
           options[:snapshot].assemble_and_store(io.phase, items, io.definition),
         {:ok, %AnalysisIO{} = analysis_io} <-
           Acceptance.run(io, snapshot_id, timing_summary) do
      {:ok, analysis_io}
    end
  end
end
