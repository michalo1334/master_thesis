defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartStudyAnalysisReply do
  @moduledoc """
  One study-analysis start reply.

  An accepted reply carries the opaque attempt identity. Every later progress,
  ready, and error event repeats that identity, so the browser can require
  exact document, mode, and attempt correlation. A rejection carries no
  attempt identity.
  """

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyRunError

  @enum_values status: [:accepted, :rejected, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :document_id, :string
    field :mode, :string
    field :attempt_id, :string
    embeds_many :errors, StudyRunError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          document_id: String.t() | nil,
          mode: String.t() | nil,
          attempt_id: String.t() | nil,
          errors: [StudyRunError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :document_id, :mode, :attempt_id])
    |> cast_embed(:errors)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["accepted", "rejected", "invalid_request"])
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> validate_format(:attempt_id, ~r/^[A-Za-z0-9_-]+$/, message: "is invalid")
    |> validate_attempt_id_for_status()
    |> Contracts.validate_uuid(:document_id)
  end

  # An accepted reply must name the attempt it started, so the browser can pin
  # events to it. A rejected reply must not carry an attempt identity.
  defp validate_attempt_id_for_status(changeset) do
    validate_change(changeset, :status, fn
      :status, "accepted" ->
        if blank?(get_field(changeset, :attempt_id)),
          do: [attempt_id: "is required for an accepted reply"],
          else: []

      :status, _status ->
        if blank?(get_field(changeset, :attempt_id)),
          do: [],
          else: [attempt_id: "must be empty unless the reply is accepted"]
    end)
  end

  defp blank?(value), do: value in [nil, ""]
end
