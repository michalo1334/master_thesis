defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Graph do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Strategy

  # One tier, one immutable graph revision, and the strategies that run on it.
  #
  # Both identifiers are canonical UUID strings. Only their shape is checked
  # here. The graph revision record is resolved before insertion, so this
  # module never reads a repository.

  @type t :: %__MODULE__{
          tier: String.t(),
          graph_revision_id: String.t(),
          initial_foothold_node_id: String.t(),
          strategies: [Strategy.t()]
        }

  embedded_schema do
    field :tier, :string
    field :graph_revision_id, :string
    field :initial_foothold_node_id, :string
    embeds_many :strategies, Strategy, on_replace: :delete
  end

  def changeset(graph, attrs) do
    graph
    |> change()
    |> cast(attrs, [:tier, :graph_revision_id, :initial_foothold_node_id])
    |> cast_embed(:strategies, required: true)
    |> validate_required([:tier, :graph_revision_id, :initial_foothold_node_id])
    |> validate_change(:graph_revision_id, &canonical_uuid/2)
    |> validate_change(:initial_foothold_node_id, &canonical_uuid/2)
  end

  defp canonical_uuid(field, value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> []
      _not_canonical -> [{field, "must be a canonical lowercase UUID"}]
    end
  end
end
