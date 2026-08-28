defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetManifestReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestSummary

  embedded_schema do
    embeds_one :manifest, ManifestSummary, on_replace: :update
  end

  @type t :: %__MODULE__{
          manifest: ManifestSummary.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:manifest)
  end
end
