defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Study do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Revisions

  # Study identity and its declared revisions.
  #
  # The revision strings are caller assertions. Only a graph revision has an
  # immutable record and a loader. Every other string is validated for
  # presence, type, and bounds, then persisted unchanged.

  @type t :: %__MODULE__{
          id: String.t(),
          revision: pos_integer(),
          revisions: Revisions.t()
        }

  embedded_schema do
    field :id, :string
    field :revision, :integer
    embeds_one :revisions, Revisions, on_replace: :update
  end

  def changeset(study, attrs) do
    study
    |> change()
    |> cast(attrs, [:id, :revision])
    |> cast_embed(:revisions, required: true)
    |> validate_required([:id, :revision])
    |> validate_number(:revision, greater_than: 0)
  end
end
