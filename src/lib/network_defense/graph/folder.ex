defmodule NetworkDefense.Graph.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.Graph

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "graph_folders" do
    field :name, :string
    has_many :graphs, Graph

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil
        }

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
