defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.ReplicaFamily do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.ReplicaSummaryAssembler

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.Canonical
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.Canonical.MeasuredReplica

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.FinalReplicaSummary
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyPhase}

  # The measured replica family of one Final collection phase.
  #
  # Each position 0..4 is assembled from the persisted records, validated as a
  # canonical measured replica, and then checked by one selector call. The
  # selector must return the replica-zero summary, so a divergent replica stops
  # the run before any snapshot exists.
  #
  # Only the replica-zero items enter the snapshot. Warm-up rows and measured
  # positions 1..4 stay stored for inspection.
  @measured_positions 0..4

  @spec run(StudyPhase.t(), Definition.t()) ::
          {:ok, [StudyCollectionItem.t()]} | {:error, StudyError.t()}
  def run(%StudyPhase{} = phase, %Definition{} = definition) do
    result =
      Enum.reduce_while(@measured_positions, {:ok, %{}}, fn position, {:ok, collected} ->
        case assemble(phase, definition, position) do
          {:ok, replica, items} ->
            {:cont, {:ok, Map.put(collected, position, {replica, items})}}

          {:error, %StudyError{} = error} ->
            {:halt, {:error, error}}
        end
      end)

    with {:ok, collected} <- result,
         {:ok, {zero_replica, zero_items}} <- fetch(collected, 0),
         {:ok, %FinalReplicaSummary{} = selected} <- select(collected),
         true <- selected == zero_replica.summary do
      {:ok, zero_items}
    else
      false -> {:error, StudyError.final_replica_mismatch()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp assemble(phase, definition, position) do
    with {:ok, summary, items} <- ReplicaSummaryAssembler.assemble(phase, definition, position),
         {:ok, replica} <-
           MeasuredReplica.validate(%MeasuredReplica{position: position, summary: summary}) do
      {:ok, replica, items}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      {:error, _reason} -> {:error, StudyError.final_replica_summary_invalid()}
    end
  end

  defp fetch(collected, position) do
    case Map.fetch(collected, position) do
      {:ok, {_replica, _items} = entry} -> {:ok, entry}
      :error -> {:error, StudyError.incomplete_final_family()}
    end
  end

  defp select(collected) do
    with {:ok, replicas} <- ordered(collected) do
      case Canonical.select(replicas) do
        {:ok, %FinalReplicaSummary{} = summary} -> {:ok, summary}
        {:error, :replica_mismatch} -> {:error, StudyError.final_replica_mismatch()}
        {:error, _reason} -> {:error, StudyError.final_replica_summary_invalid()}
      end
    end
  end

  defp ordered(collected) do
    result =
      Enum.reduce_while(@measured_positions, {:ok, []}, fn position, {:ok, replicas} ->
        case fetch(collected, position) do
          {:ok, {replica, _items}} -> {:cont, {:ok, [replica | replicas]}}
          {:error, %StudyError{} = error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, replicas} <- result, do: {:ok, Enum.reverse(replicas)}
  end
end
