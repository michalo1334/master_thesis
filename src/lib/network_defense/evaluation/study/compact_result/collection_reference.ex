defmodule NetworkDefense.Evaluation.Study.CompactResult.CollectionReference do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  @fields [:phase_id, :gust_run_id, :snapshot_id]

  embedded_schema do
    field :phase_id, :binary_id
    field :gust_run_id, :integer
    field :snapshot_id, :binary_id
  end

  @type t :: %__MODULE__{
          phase_id: Ecto.UUID.t(),
          gust_run_id: pos_integer(),
          snapshot_id: Ecto.UUID.t()
        }

  def changeset(reference, attrs) do
    reference
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:gust_run_id, greater_than: 0)
  end
end
