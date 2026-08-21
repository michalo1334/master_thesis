defmodule NetworkDefense.ReportProgress do
  @moduledoc """
  Shared report-assembly progress callback for report generators.

  Every `generate`/`get_report`/`report` that streams assembly progress takes
  an `on_progress` callback of this shape, called with the loaded graph
  identity and a completed-step counter.
  """

  @type progress_callback ::
          (String.t(), String.t(), non_neg_integer(), pos_integer(), String.t() -> :ok)

  @spec noop() :: progress_callback()
  def noop, do: fn _graph_id, _graph_revision_id, _completed, _total, _detail -> :ok end
end
