defmodule NetworkDefense.Evaluation2.Study.Page do
  @moduledoc """
  One bounded page of a study list read.

  A page holds one kind of entry: `RevisionSummary` or `ExecutionSummary`
  values. `page` is one-based, and the supported facade bounds `page_size`
  before any query runs. `total` counts every stored entry that matches the
  request, so `more?/1` recognizes a further page without a second read.

  Entry order is stable. Revisions follow study identifier and descending
  revision number; executions follow descending start time and descending
  execution identifier.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.ExecutionSummary
  alias NetworkDefense.Evaluation2.Study.RevisionSummary

  @typedoc "One entry of one bounded study list."
  @type entry :: RevisionSummary.t() | ExecutionSummary.t()

  @type t :: %__MODULE__{
          entries: [entry()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer()
        }

  defstruct [:entries, :page, :page_size, :total]

  @default_size 25
  @max_size 100

  @doc "Return the page size that a request without one receives."
  @spec default_size() :: pos_integer()
  def default_size, do: @default_size

  @doc "Return the largest accepted page size."
  @spec max_size() :: pos_integer()
  def max_size, do: @max_size

  @doc "Return whether the stored list holds entries after this page."
  @spec more?(t()) :: boolean()
  def more?(%__MODULE__{page: page, page_size: page_size, total: total}) do
    page * page_size < total
  end
end
