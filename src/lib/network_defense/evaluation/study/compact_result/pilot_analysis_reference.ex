defmodule NetworkDefense.Evaluation.Study.CompactResult.PilotAnalysisReference do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.PilotOutcome

  embedded_schema do
    field :phase_id, :binary_id
    field :gust_run_id, :integer
    field :outcome, :any, virtual: true
  end

  @type t :: %__MODULE__{
          phase_id: Ecto.UUID.t(),
          gust_run_id: pos_integer(),
          outcome: PilotOutcome.t()
        }

  def changeset(reference, attrs) do
    reference
    |> cast(attrs, [:phase_id, :gust_run_id])
    |> validate_required([:phase_id, :gust_run_id])
    |> validate_number(:gust_run_id, greater_than: 0)
    |> put_outcome(attrs["outcome"])
  end

  defp put_outcome(changeset, attrs) do
    case PilotOutcome.parse(attrs) do
      {:ok, outcome} -> put_change(changeset, :outcome, outcome)
      {:error, _error} -> add_error(changeset, :outcome, "is invalid")
    end
  end
end
