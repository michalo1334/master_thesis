defmodule NetworkDefense.Evaluation.Study.CompactResult.AnalysisReference do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  @fields [:phase_id, :gust_run_id]

  embedded_schema do
    field :phase_id, :binary_id
    field :gust_run_id, :integer
  end

  @type t :: %__MODULE__{phase_id: Ecto.UUID.t(), gust_run_id: pos_integer()}

  def changeset(reference, attrs) do
    reference
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:gust_run_id, greater_than: 0)
  end
end
