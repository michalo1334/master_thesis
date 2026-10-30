defmodule NetworkDefense.Evaluation2.Study.Pilot.CollectionContract do
  @moduledoc """
  Transport contract of one Pilot Collection Gust run.

  The phase run identifies the ordered work of the run, so the input carries the
  phase-run UUID and nothing else. The Pilot collection phase owns the assembled
  `EvidenceSnapshot`, so the terminal output is empty: a succeeded run is the
  completion fact, and the snapshot is read through its owning phase.

  The transport is strict. The input accepts one canonical UUID, and the output
  accepts the empty object only.
  """
  use NetworkDefense.Evaluation2.Study.Workflow.CollectionContract
end
