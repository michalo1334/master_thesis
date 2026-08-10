defmodule NetworkDefense.Graph.Errors do
  @moduledoc false

  @codes [
    :not_found,
    :invalid_graph,
    :invalid_base_revision,
    :invalid_node,
    :invalid_edge,
    :invalid_endpoints,
    :multiple_segments,
    :multiple_runs,
    :invalid_mission_capability_support,
    :duplicate_ids,
    :identity_belongs_to_another_graph,
    :invalid_folder,
    :folder_not_found,
    :internal_error
  ]

  @type code ::
          :not_found
          | :invalid_graph
          | :invalid_base_revision
          | :invalid_node
          | :invalid_edge
          | :invalid_endpoints
          | :multiple_segments
          | :multiple_runs
          | :invalid_mission_capability_support
          | :duplicate_ids
          | :identity_belongs_to_another_graph
          | :invalid_folder
          | :folder_not_found
          | :internal_error

  @spec codes() :: [code()]
  def codes, do: @codes
end
