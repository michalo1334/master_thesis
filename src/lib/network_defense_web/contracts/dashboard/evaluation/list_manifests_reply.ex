defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListManifestsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestSummary

  embedded_schema do
    embeds_many :manifests, ManifestSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{manifests: [ManifestSummary.t()]}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:manifests)
  end
end
