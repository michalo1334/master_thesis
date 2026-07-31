defmodule NetworkDefenseWeb.Web.Contracts.CreateConnectionDraftPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @node_types NetworkDefense.Nodes.Registry.contract_types()
  @relationship_types NetworkDefense.Relationships.Registry.contract_types()

  @enum_values source_type: @node_types, relationship_type: @relationship_types

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :relationship_type, :string
    field :source_id, :string
    field :source_type, :string
    field :source_is_from, :boolean
    field :target_id, :string
    field :target_type, :string
    field :new_node_type, :string
    field :x_pos, :float
    field :y_pos, :float
  end

  @type t :: %__MODULE__{
          relationship_type: String.t(),
          source_id: String.t(),
          source_type: String.t(),
          source_is_from: boolean(),
          target_id: String.t() | nil,
          target_type: String.t() | nil,
          new_node_type: String.t() | nil,
          x_pos: float() | nil,
          y_pos: float() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :relationship_type,
      :source_id,
      :source_type,
      :source_is_from,
      :target_id,
      :target_type,
      :new_node_type,
      :x_pos,
      :y_pos
    ])
    |> validate_required([:relationship_type, :source_id, :source_type, :source_is_from])
    |> Contracts.validate_uuid(:source_id)
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:source_type, @node_types)
    |> validate_target()
  end

  defp validate_target(changeset) do
    case {get_field(changeset, :target_id), get_field(changeset, :new_node_type)} do
      {target_id, nil} when is_binary(target_id) ->
        changeset
        |> Contracts.validate_uuid(:target_id)
        |> validate_required([:target_type])
        |> validate_inclusion(:target_type, @node_types)

      {nil, new_node_type} when is_binary(new_node_type) ->
        changeset
        |> validate_required([:x_pos, :y_pos])
        |> validate_inclusion(:new_node_type, @node_types)

      _ ->
        add_error(changeset, :target_id, "or new_node_type is required")
    end
  end
end
