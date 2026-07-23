defmodule NetworkDefense.Graph.Contracts.Data.HostData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :dashboard

  embedded_schema do
    field :name, :string
  end

  @type t :: %__MODULE__{
          name: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
