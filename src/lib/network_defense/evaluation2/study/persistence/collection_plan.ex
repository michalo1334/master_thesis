defmodule NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan do
  @moduledoc false

  # Immutable ordered work of one collection phase run.
  #
  # One plan belongs to one collection `StudyPhaseRun`, so every replica of that
  # run reuses one resolved request list. The item position identifies the request
  # that one `CollectionItem` executes.
  #
  # The stored `items` column is one JSON object with the ordered `WorkItem` list
  # under the `"items"` key, because an Ecto `:map` field holds one JSON object.
  # `payload/0` names that object, and the persistence boundary decodes it back
  # into the typed list. The embedded Spectral metadata keeps `payload/0`
  # available when the release strips BEAM debug information.

  use Ecto.Schema
  use Spectral

  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "JSONB payload of one plan: the ordered item list under the `items` key."
  @type payload :: %{items: [WorkItem.t()]}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_run_id: Ecto.UUID.t(),
          items: [WorkItem.t()],
          inserted_at: DateTime.t()
        }

  schema "evaluation2_collection_plans" do
    field :study_phase_run_id, :binary_id
    field :items, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
