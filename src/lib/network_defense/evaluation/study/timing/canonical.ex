defmodule NetworkDefense.Evaluation.Study.Timing.Canonical do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary

  defmodule MeasuredReplica do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :position, :integer
      embeds_one :summary, FinalReplicaSummary, on_replace: :update
    end

    @type t :: %__MODULE__{position: 0..4, summary: FinalReplicaSummary.t()}

    @type changeset_source :: %__MODULE__{
            position: integer() | nil,
            summary: FinalReplicaSummary.t() | nil
          }

    @type error :: :invalid_measured_replica

    @spec new(map()) :: {:ok, t()} | {:error, error()}
    def new(attrs) when is_map(attrs) do
      %__MODULE__{}
      |> changeset(attrs)
      |> apply_action(:validate)
      |> case do
        {:ok, %__MODULE__{} = replica} -> validate(replica)
        {:error, %Ecto.Changeset{}} -> {:error, :invalid_measured_replica}
      end
    end

    def new(_attrs), do: {:error, :invalid_measured_replica}

    @spec validate(term()) :: {:ok, t()} | {:error, error()}
    def validate(%__MODULE__{position: position, summary: %FinalReplicaSummary{} = summary})
        when position in 0..4 do
      case FinalReplicaSummary.validate(summary) do
        {:ok, summary} -> {:ok, %__MODULE__{position: position, summary: summary}}
        {:error, _error} -> {:error, :invalid_measured_replica}
      end
    end

    def validate(_replica), do: {:error, :invalid_measured_replica}

    @spec changeset(changeset_source(), map()) :: Ecto.Changeset.t()
    def changeset(replica, attrs) do
      replica
      |> cast(attrs, [:position])
      |> cast_embed(:summary, required: true)
      |> validate_required([:position])
      |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
    end
  end

  @type error :: :invalid_measured_replicas | :replica_mismatch

  @spec select([MeasuredReplica.t()]) :: {:ok, FinalReplicaSummary.t()} | {:error, error()}
  def select(replicas) when is_list(replicas) do
    with {:ok, replicas} <- validate_replicas(replicas),
         :ok <- validate_positions(replicas),
         :ok <- validate_summaries(replicas) do
      {:ok, summary_at_zero(replicas)}
    end
  end

  def select(_replicas), do: {:error, :invalid_measured_replicas}

  defp validate_replicas(replicas) do
    result =
      Enum.reduce_while(replicas, [], fn replica, validated ->
        case MeasuredReplica.validate(replica) do
          {:ok, replica} -> {:cont, [replica | validated]}
          {:error, _error} -> {:halt, {:error, :invalid_measured_replicas}}
        end
      end)

    case result do
      {:error, _error} = error -> error
      validated -> {:ok, Enum.reverse(validated)}
    end
  end

  defp validate_positions(replicas) do
    if Enum.sort(Enum.map(replicas, & &1.position)) == [0, 1, 2, 3, 4],
      do: :ok,
      else: {:error, :invalid_measured_replicas}
  end

  defp validate_summaries([%MeasuredReplica{summary: summary} | rest]) do
    if Enum.all?(rest, &(&1.summary == summary)),
      do: :ok,
      else: {:error, :replica_mismatch}
  end

  defp summary_at_zero(replicas) do
    Enum.find_value(replicas, fn
      %MeasuredReplica{position: 0, summary: summary} -> summary
      %MeasuredReplica{} -> nil
    end)
  end
end
