defmodule NetworkDefense.Optimization.ModelVariant do
  @moduledoc false

  @variants [
    blast_only: %{
      objective: :blast_radius_only,
      require_pre_attack_feasibility: true
    },
    blast_only_unconstrained: %{
      objective: :blast_radius_only,
      require_pre_attack_feasibility: false
    },
    mission_only: %{
      objective: :mission_impact_only,
      require_pre_attack_feasibility: true
    },
    mission_only_unconstrained: %{
      objective: :mission_impact_only,
      require_pre_attack_feasibility: false
    },
    full: %{
      objective: :mission_then_blast_radius,
      require_pre_attack_feasibility: true
    },
    full_unconstrained: %{
      objective: :mission_then_blast_radius,
      require_pre_attack_feasibility: false
    }
  ]
  @values Keyword.keys(@variants)
  @wire_values Enum.map(@values, &Atom.to_string/1)

  @type t ::
          :blast_only
          | :blast_only_unconstrained
          | :mission_only
          | :mission_only_unconstrained
          | :full
          | :full_unconstrained

  @spec values() :: [t()]
  def values, do: @values

  @spec wire_values() :: [String.t()]
  def wire_values, do: @wire_values

  @spec from_wire(String.t()) :: {:ok, t()} | :error
  def from_wire(wire) when wire in @wire_values, do: {:ok, String.to_existing_atom(wire)}
  def from_wire(_wire), do: :error

  @spec to_wire(t()) :: String.t()
  def to_wire(variant), do: Atom.to_string(variant)

  @spec definition(t()) :: map()
  def definition(variant), do: Keyword.fetch!(@variants, variant)
end
