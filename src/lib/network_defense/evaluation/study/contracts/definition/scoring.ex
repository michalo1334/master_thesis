defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Scoring do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # The optimization-scoring simulation of one simulation-backed strategy.
  #
  # Scoring builds a short-lived simulation for every candidate action set and
  # ranks the result. It is separate from evidence collection: a scoring trial
  # count is an optimizer cost, not a study observation count.
  #
  # The search schedule, the temperature schedule, and the objective weights
  # stay fixed in code. They are versioned algorithm semantics, so this block
  # declares inputs only and never a tuning knob.

  @type t :: %__MODULE__{
          objective: String.t(),
          monte_carlo_trials: pos_integer(),
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [String.t()]
        }

  embedded_schema do
    field :objective, :string
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :max_attempts, :integer
    field :rules, {:array, :string}
  end

  @fields [
    :objective,
    :monte_carlo_trials,
    :iterations_per_run,
    :max_attempts,
    :rules
  ]

  def changeset(scoring, attrs) do
    scoring
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_length(:rules, min: 1)
  end
end
