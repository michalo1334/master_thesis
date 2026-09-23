defmodule NetworkDefense.Graph.Contracts.Variant do
  @moduledoc false

  import Ecto.Changeset

  def validate_data(changeset, variants) do
    case for_type(get_field(changeset, :type), variants) do
      {:ok, {data_contract, _domain_type}} ->
        case data_contract.validate(get_field(changeset, :data) || %{}) do
          {:ok, data} ->
            put_change(changeset, :data, data)

          {:error, data_changeset} ->
            add_error(changeset, :data, "is invalid", nested_changeset: data_changeset)
        end

      :error ->
        add_error(changeset, :type, "is invalid")
    end
  end

  def for_type(type, variants) when is_binary(type) do
    case Enum.find(variants, fn {tag, _variant} -> Atom.to_string(tag) == type end) do
      nil -> :error
      {_tag, variant} -> {:ok, variant}
    end
  end

  def for_type(_type, _variants), do: :error

  def for_domain(type, variants) when is_atom(type) do
    case Enum.find(variants, fn {_tag, {_data_contract, domain_type}} -> domain_type == type end) do
      nil -> :error
      {tag, {data_contract, _domain_type}} -> {:ok, {tag, data_contract}}
    end
  end

  def for_domain(_type, _variants), do: :error
end
