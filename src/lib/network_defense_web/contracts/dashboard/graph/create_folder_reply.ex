defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateFolderReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.FolderSummary

  @enum_values status: [:ok, :invalid_folder, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string

    embeds_one :folder, FolderSummary, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          folder: FolderSummary.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:folder)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "invalid_folder", "unmapped_error"])
  end
end
