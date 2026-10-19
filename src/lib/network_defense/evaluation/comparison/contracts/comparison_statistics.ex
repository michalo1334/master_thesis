defmodule NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonRequest}
  alias NetworkDefense.Evaluation.Comparison.SchemaValidator

  @type t :: %__MODULE__{}

  embedded_schema do
    field :schema_version, :integer
    field :method, :string
    field :estimate, :map
    field :interval, :map
    field :test, :map
    field :assessment, :map
  end

  def changeset(statistics, attrs) do
    statistics
    |> change()
    |> SchemaValidator.matches_schema(attrs, :statistics)
    |> cast_if_schema_valid(attrs)
  end

  def changeset(statistics, attrs, %ComparisonRequest{} = request) do
    statistics
    |> changeset(attrs)
    |> validate_result_relations(request)
  end

  def parse(attrs, %ComparisonRequest{} = request) do
    changeset = changeset(%__MODULE__{}, attrs, request)

    case apply_action(changeset, :validate) do
      {:ok, statistics} ->
        {:ok, statistics}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           ComparisonError.invalid_response_contract()
         )}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    cast(changeset, attrs, [
      :schema_version,
      :method,
      :estimate,
      :interval,
      :test,
      :assessment
    ])
  end

  defp validate_result_relations(%Ecto.Changeset{valid?: false} = changeset, _request),
    do: changeset

  defp validate_result_relations(changeset, request) do
    interval = get_field(changeset, :interval)
    test = get_field(changeset, :test)

    with %{"lower" => lower, "upper" => upper, "confidence_level" => confidence_level} <-
           interval,
         %{"alternative" => alternative} <- test,
         true <- is_number(lower) and is_number(upper) and lower <= upper,
         true <- confidence_level == request.interval.confidence_level,
         true <- alternative == request.test.alternative do
      changeset
    else
      _invalid -> add_error(changeset, :base, "result relations are invalid")
    end
  end
end
