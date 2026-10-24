defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.PilotAnalysis do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # Pilot precision settings, the selection rule, and the stream base seed.
  #
  # These values drive the bounded precision estimate. The base seed starts the
  # historical comparison stream:
  #
  #     stream_seed = base_seed + tier_rank * tier_stride + comparison_index * comparison_stride
  #
  # Both strides are fixed semantics of the current Pilot work mapping, so this
  # block declares the base seed only.

  @type t :: %__MODULE__{
          base_seed: non_neg_integer(),
          outer_subsamples: pos_integer(),
          target_half_width: float(),
          guard_quantile: float(),
          confidence_level: float(),
          bootstrap_replicates: pos_integer(),
          selection_rule: String.t()
        }

  embedded_schema do
    field :base_seed, :integer
    field :outer_subsamples, :integer
    field :target_half_width, :float
    field :guard_quantile, :float
    field :confidence_level, :float
    field :bootstrap_replicates, :integer
    field :selection_rule, :string
  end

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [
      :base_seed,
      :outer_subsamples,
      :target_half_width,
      :guard_quantile,
      :confidence_level,
      :bootstrap_replicates,
      :selection_rule
    ])
    |> validate_required([
      :base_seed,
      :outer_subsamples,
      :target_half_width,
      :guard_quantile,
      :confidence_level,
      :bootstrap_replicates,
      :selection_rule
    ])
    |> validate_number(:base_seed, greater_than_or_equal_to: 0)
    |> validate_number(:outer_subsamples, greater_than: 0)
    |> validate_number(:target_half_width, greater_than: 0)
    |> validate_number(:guard_quantile, greater_than: 0, less_than: 1)
    |> validate_number(:confidence_level, greater_than: 0, less_than: 1)
    |> validate_number(:bootstrap_replicates, greater_than: 0)
  end
end
