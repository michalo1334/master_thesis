defmodule NetworkDefense.Graph.Contracts.Data.NetworkSegmentData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph
  alias NetworkDefense.NetworkCidr

  embedded_schema do
    field :name, :string
    field :cidr, :string
  end

  @type t :: %__MODULE__{
          name: String.t(),
          cidr: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :cidr])
    |> validate_required([:name])
    |> validate_change(:cidr, fn :cidr, cidr ->
      if is_nil(cidr) or NetworkCidr.valid?(cidr), do: [], else: [cidr: "must be a valid CIDR"]
    end)
  end
end
