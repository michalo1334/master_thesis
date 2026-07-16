defmodule NetworkDefense.UnitOfWork do
  @moduledoc """
  Collects explicit database operations for one transaction.
  """

  alias Ecto.Multi

  defstruct inserts: [], updates: [], deletes: [], delete_all: []

  def new, do: %__MODULE__{}

  def insert(unit_of_work, changeset) do
    key = key(changeset.data)

    %{
      unit_of_work
      | inserts: replace_or_prepend(unit_of_work.inserts, changeset, key),
        updates: remove(unit_of_work.updates, key),
        deletes: remove(unit_of_work.deletes, key)
    }
  end

  def update(unit_of_work, changeset) do
    key = key(changeset.data)

    if Enum.any?(unit_of_work.inserts, &(key(&1.data) == key)) do
      %{unit_of_work | inserts: replace_or_prepend(unit_of_work.inserts, changeset, key)}
    else
      %{unit_of_work | updates: replace_or_prepend(unit_of_work.updates, changeset, key)}
    end
  end

  def delete(unit_of_work, struct) do
    key = key(struct)

    if Enum.any?(unit_of_work.inserts, &(key(&1.data) == key)) do
      %{
        unit_of_work
        | inserts: remove(unit_of_work.inserts, key),
          updates: remove(unit_of_work.updates, key)
      }
    else
      %{
        unit_of_work
        | deletes: replace_or_prepend(unit_of_work.deletes, struct, key),
          updates: remove(unit_of_work.updates, key)
      }
    end
  end

  def delete_all(unit_of_work, query) do
    %{unit_of_work | delete_all: [query | unit_of_work.delete_all]}
  end

  def commit(unit_of_work, repo) do
    Multi.new()
    |> add_delete_all(Enum.reverse(unit_of_work.delete_all))
    |> add_deletes(Enum.reverse(unit_of_work.deletes))
    |> add_inserts(Enum.reverse(unit_of_work.inserts))
    |> add_updates(Enum.reverse(unit_of_work.updates))
    |> repo.transaction()
  end

  defp add_delete_all(multi, queries),
    do: add_operations(multi, queries, :delete_all, &Multi.delete_all/4)

  defp add_deletes(multi, structs), do: add_operations(multi, structs, :delete, &Multi.delete/4)

  defp add_inserts(multi, changesets),
    do: add_operations(multi, changesets, :insert, &Multi.insert/4)

  defp add_updates(multi, changesets),
    do: add_operations(multi, changesets, :update, &Multi.update/4)

  defp add_operations(multi, operations, type, operation) do
    Enum.with_index(operations)
    |> Enum.reduce(multi, fn {value, index}, multi ->
      operation.(multi, {type, index}, value, [])
    end)
  end

  defp replace_or_prepend(records, record, key) do
    case Enum.find_index(records, fn existing -> key(record_data(existing)) == key end) do
      nil -> [record | records]
      index -> List.replace_at(records, index, record)
    end
  end

  defp remove(records, key),
    do: Enum.reject(records, fn record -> key(record_data(record)) == key end)

  defp record_data(%Ecto.Changeset{data: data}), do: data
  defp record_data(record), do: record
  defp key(struct), do: {struct.__struct__, struct.id}
end
