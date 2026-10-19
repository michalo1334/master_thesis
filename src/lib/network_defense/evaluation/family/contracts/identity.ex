defmodule NetworkDefense.Evaluation.Family.Contracts.Identity do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Stable identity of one primary comparison inside a declared family.
  #
  # Equality uses the typed five-field tuple. Encoded JSON text is never
  # compared, so JSON object-field order cannot change the identity.

  @type t :: %__MODULE__{
          tier: String.t(),
          budget: pos_integer(),
          alternative: String.t(),
          reference: String.t(),
          outcome: String.t()
        }

  @typedoc "Canonical ordered identity key. Two identities are equal when their keys are equal."
  @type key :: {String.t(), pos_integer(), String.t(), String.t(), String.t()}

  @fields [:tier, :budget, :alternative, :reference, :outcome]
  @identifier_fields [:tier, :alternative, :reference, :outcome]
  @field_names Enum.map(@fields, &Atom.to_string/1)
  @identifier ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/

  embedded_schema do
    field(:tier, :string)
    field(:budget, :integer)
    field(:alternative, :string)
    field(:reference, :string)
    field(:outcome, :string)
  end

  def changeset(identity, attrs) when is_map(attrs) do
    if Enum.all?(Map.keys(attrs), &is_binary/1) do
      identity
      |> cast(attrs, @fields)
      |> validate_required(@fields)
      |> validate_raw_budget(attrs)
      |> validate_number(:budget, greater_than: 0)
      |> validate_identifiers()
      |> validate_exact_keys(attrs)
    else
      identity |> change() |> add_error(:base, "has invalid fields")
    end
  end

  def changeset(identity, _attrs) do
    identity |> change() |> add_error(:base, "must be a map")
  end

  defp validate_raw_budget(changeset, attrs) do
    case Map.fetch(attrs, "budget") do
      {:ok, budget} when is_integer(budget) -> changeset
      {:ok, _budget} -> add_error(changeset, :budget, "must be an integer")
      :error -> changeset
    end
  end

  defp validate_identifiers(changeset) do
    Enum.reduce(@identifier_fields, changeset, fn field, changeset ->
      validate_format(changeset, field, @identifier)
    end)
  end

  defp validate_exact_keys(changeset, attrs) do
    keys = Map.keys(attrs)

    if Enum.sort(keys) == Enum.sort(@field_names),
      do: changeset,
      else: add_error(changeset, :base, "has invalid fields")
  end

  @spec key(t()) :: key()
  def key(%__MODULE__{} = identity) do
    {identity.tier, identity.budget, identity.alternative, identity.reference, identity.outcome}
  end

  def matches?(%__MODULE__{} = left, %__MODULE__{} = right), do: key(left) == key(right)
  def matches?(_left, _right), do: false

  @spec new(term()) :: {:ok, t()} | :error
  def new(attrs) do
    case apply_action(changeset(%__MODULE__{}, attrs), :validate) do
      {:ok, identity} -> {:ok, identity}
      {:error, _changeset} -> :error
    end
  end
end
