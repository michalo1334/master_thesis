defmodule NetworkDefense.Contracts do
  @moduledoc false

  import Ecto.Changeset,
    only: [
      cast: 3,
      cast: 4,
      cast_embed: 2,
      cast_embed: 3,
      get_field: 2,
      validate_change: 3,
      validate_inclusion: 3,
      validate_required: 2
    ]

  defmacro __using__(options) do
    category = Keyword.get(options, :category)

    unless is_nil(category) or is_atom(category) do
      raise ArgumentError, "contract category must be an atom"
    end

    quote do
      use Ecto.Schema
      import Ecto.Changeset
      alias NetworkDefense.Contracts

      @primary_key false

      def __contract__, do: true
      def contract_category, do: unquote(category)
      def contract_meta, do: %{}
      defoverridable contract_meta: 0

      def validate(attrs) when is_map(attrs) do
        struct(__MODULE__)
        |> changeset(attrs)
        |> apply_action(:validate)
      end

      def to_wire(contract), do: Contracts.to_wire(contract)
      def to_params(contract), do: Contracts.to_params(contract)
    end
  end

  def to_wire(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {key, to_wire(value)} end)
  end

  def to_wire(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, to_wire(value)} end)

  def to_wire(list) when is_list(list), do: Enum.map(list, &to_wire/1)
  def to_wire(value), do: value

  def to_params(%_{} = struct), do: struct |> Map.from_struct() |> to_params()

  def to_params(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_params(value)} end)
  end

  def to_params(list) when is_list(list), do: Enum.map(list, &to_params/1)
  def to_params(value), do: value

  def validate_uuid(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> []
        :error -> [{field, "is invalid"}]
      end
    end)
  end

  def run_reply_meta, do: %{enum_values: [status: [:accepted, :rejected]]}

  def run_reply_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :graph_revision_id, :correlation_id, :run_id], empty_values: [])
    |> cast_embed(:error)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["accepted", "rejected"])
    |> validate_rejected_error()
  end

  def graph_revision_ids_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_ids])
    |> validate_change(:graph_revision_ids, fn :graph_revision_ids, revision_ids ->
      if Enum.all?(revision_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [graph_revision_ids: "contains an invalid UUID"]
      end
    end)
  end

  def report_request_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["processing", "unavailable", "invalid_params"])
  end

  def run_reference_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:kind, :run_id])
    |> validate_required([:kind, :run_id])
    |> validate_inclusion(:kind, ["simulation", "optimization", "evaluation"])
    |> validate_uuid(:run_id)
  end

  def run_failure_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :graph_revision_id])
    |> cast_embed(:error, required: true)
    |> validate_required([:correlation_id, :graph_id, :graph_revision_id])
  end

  defp validate_rejected_error(changeset) do
    if get_field(changeset, :status) == "rejected" do
      validate_required(changeset, :error)
    else
      changeset
    end
  end
end
