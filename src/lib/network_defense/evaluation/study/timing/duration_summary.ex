defmodule NetworkDefense.Evaluation.Study.Timing.DurationSummary do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # One duration type of one declared Final tier. The five measured values keep
  # their measured-position order; the median comes from a sorted copy, so the
  # stored list is never reordered. The minimum and maximum describe the observed
  # inclusive range. They are not a confidence interval.

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @value_count 5
  @median_index 2

  @type t :: %__MODULE__{
          values_us: [non_neg_integer()],
          median_us: non_neg_integer(),
          minimum_us: non_neg_integer(),
          maximum_us: non_neg_integer()
        }

  embedded_schema do
    field :values_us, {:array, :integer}
    field :median_us, :integer
    field :minimum_us, :integer
    field :maximum_us, :integer
  end

  @spec summarize([non_neg_integer()]) :: {:ok, t()} | {:error, StudyError.t()}
  def summarize(values) when is_list(values) do
    if length(values) == @value_count and Enum.all?(values, &elapsed_us?/1) do
      sorted = Enum.sort(values)

      {:ok,
       %__MODULE__{
         values_us: values,
         median_us: Enum.at(sorted, @median_index),
         minimum_us: Enum.min(values),
         maximum_us: Enum.max(values)
       }}
    else
      {:error, StudyError.final_timing_incomplete()}
    end
  end

  def summarize(_values), do: {:error, StudyError.final_timing_incomplete()}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:values_us, :median_us, :minimum_us, :maximum_us])
    |> validate_required([:values_us, :median_us, :minimum_us, :maximum_us])
    |> validate_length(:values_us, is: @value_count)
    |> validate_change(:values_us, &validate_elapsed_values/2)
    |> validate_number(:median_us, greater_than_or_equal_to: 0)
    |> validate_number(:minimum_us, greater_than_or_equal_to: 0)
    |> validate_number(:maximum_us, greater_than_or_equal_to: 0)
    |> validate_derived_values()
  end

  defp validate_elapsed_values(:values_us, values) do
    if Enum.all?(values, &elapsed_us?/1),
      do: [],
      else: [values_us: "must hold non-negative integer microseconds"]
  end

  defp validate_derived_values(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_derived_values(changeset) do
    values = get_field(changeset, :values_us)
    sorted = Enum.sort(values)

    [
      {:median_us, Enum.at(sorted, @median_index)},
      {:minimum_us, Enum.min(values)},
      {:maximum_us, Enum.max(values)}
    ]
    |> Enum.reduce(changeset, fn {field, expected}, changeset ->
      if get_field(changeset, field) == expected,
        do: changeset,
        else: add_error(changeset, field, "does not match the measured values")
    end)
  end

  defp elapsed_us?(value), do: is_integer(value) and value >= 0
end
