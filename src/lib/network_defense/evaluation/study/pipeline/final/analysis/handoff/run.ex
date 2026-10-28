defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Handoff.Run do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # One collected tier inside the persisted Final handoff. The reference stays
  # compact: the stored Gust run owns the task history.

  @type t :: %__MODULE__{
          tier: String.t(),
          tier_position: non_neg_integer(),
          gust_run_id: pos_integer()
        }

  embedded_schema do
    field :tier, :string
    field :tier_position, :integer
    field :gust_run_id, :integer
  end

  @spec new(String.t(), non_neg_integer(), integer()) :: t()
  def new(tier, tier_position, gust_run_id) do
    %__MODULE__{
      tier: tier,
      tier_position: tier_position,
      gust_run_id: gust_run_id
    }
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:tier, :tier_position, :gust_run_id])
    |> validate_required([:tier, :tier_position, :gust_run_id])
    |> validate_change(:tier, fn _field, tier ->
      if is_binary(tier) and String.trim(tier) != "",
        do: [],
        else: [tier: "must be a declared tier name"]
    end)
    |> validate_number(:tier_position, greater_than_or_equal_to: 0)
    |> validate_number(:gust_run_id, greater_than: 0)
  end
end
