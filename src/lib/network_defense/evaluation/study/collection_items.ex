defmodule NetworkDefense.Evaluation.Study.CollectionItems do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyCollectionItem
  alias NetworkDefense.Repo

  # The stable positional identity of one collection item.
  #
  # A task of one study phase collects one declared position: one replica
  # position and one item position inside that replica. The database holds one
  # row for that tuple, so a repeated request reads the stored item instead of
  # creating a second domain effect.
  #
  # The request is answered with one conditional insert and a read-back of the
  # same identity. The insert reports no conflict, so a repeated call and a
  # concurrent duplicate both read the one stored row. A phase identifier that
  # names no stored phase reports an unavailable store.

  @spec get_or_create(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, StudyCollectionItem.t()} | {:error, StudyError.t()}
  def get_or_create(study_phase_id, replica_position, item_position) do
    with {:ok, phase_id} <- cast_phase_id(study_phase_id),
         :ok <- validate_position(:replica_position, replica_position),
         :ok <- validate_position(:item_position, item_position) do
      attrs = %{
        study_phase_id: phase_id,
        replica_position: replica_position,
        item_position: item_position
      }

      insert(attrs)
    end
  end

  defp cast_phase_id(study_phase_id) do
    case Ecto.UUID.cast(study_phase_id) do
      {:ok, phase_id} -> {:ok, phase_id}
      :error -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp validate_position(_field, position) when is_integer(position) and position >= 0, do: :ok

  defp validate_position(field, _position),
    do: {:error, StudyError.invalid_collection_position(field)}

  defp insert(attrs) do
    %StudyCollectionItem{}
    |> StudyCollectionItem.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:study_phase_id, :replica_position, :item_position]
    )
    |> case do
      {:ok, _inserted} -> stored(attrs)
      {:error, _changeset} -> {:error, StudyError.collection_item_storage_failed()}
    end
  end

  defp stored(attrs) do
    case Repo.get_by(StudyCollectionItem, attrs) do
      nil -> {:error, StudyError.collection_item_storage_failed()}
      %StudyCollectionItem{} = item -> {:ok, item}
    end
  end
end
