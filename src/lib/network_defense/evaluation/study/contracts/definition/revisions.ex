defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Revisions do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # Declared revision strings for one study definition.
  #
  # The application holds no immutable record for these values. They state what
  # the study claims it ran, so a later reader can detect drift. They are not
  # authenticated provenance.

  @fields [
    :model,
    :attacker,
    :defense,
    :rule,
    :strategy,
    :software,
    :application,
    :compute,
    :dependency,
    :environment
  ]

  @type t :: %__MODULE__{
          model: String.t(),
          attacker: String.t(),
          defense: String.t(),
          rule: String.t(),
          strategy: String.t(),
          software: String.t(),
          application: String.t(),
          compute: String.t(),
          dependency: String.t(),
          environment: String.t()
        }

  embedded_schema do
    field(:model, :string)
    field(:attacker, :string)
    field(:defense, :string)
    field(:rule, :string)
    field(:strategy, :string)
    field(:software, :string)
    field(:application, :string)
    field(:compute, :string)
    field(:dependency, :string)
    field(:environment, :string)
  end

  def changeset(revisions, attrs) do
    revisions
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
