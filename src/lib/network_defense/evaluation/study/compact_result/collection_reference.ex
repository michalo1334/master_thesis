defmodule NetworkDefense.Evaluation.Study.CompactResult.CollectionReference do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  import Ecto.Changeset

  # One collection phase reference.
  #
  # A collection phase owns an ordered list of Gust runs. The Pilot collection
  # holds one run. The Final collection holds one run for each declared tier, in
  # the first-seen comparison order. The stored order is meaningful, so the list
  # is validated as written and never sorted here.

  @fields [:phase_id, :gust_run_ids, :snapshot_id]

  embedded_schema do
    field :phase_id, :binary_id
    field :gust_run_ids, {:array, :integer}
    field :snapshot_id, :binary_id
  end

  @type t :: %__MODULE__{
          phase_id: Ecto.UUID.t(),
          gust_run_ids: [pos_integer()],
          snapshot_id: Ecto.UUID.t()
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reference, attrs) do
    reference
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_change(:gust_run_ids, &run_ids/2)
  end

  defp run_ids(:gust_run_ids, ids) do
    cond do
      ids == [] ->
        [gust_run_ids: "must contain at least one run"]

      not Enum.all?(ids, &(is_integer(&1) and &1 > 0)) ->
        [gust_run_ids: "must contain positive runs"]

      length(Enum.uniq(ids)) != length(ids) ->
        [gust_run_ids: "must be unique"]

      true ->
        []
    end
  end
end
