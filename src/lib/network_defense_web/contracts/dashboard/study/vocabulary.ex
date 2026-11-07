defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Vocabulary do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefenseWeb.Contracts.Dashboard.Study.Definition
  alias NetworkDefenseWeb.StudyRequests

  embedded_schema do
    field :state, :string
    field :phase, :string
    field :tier, :string
    field :outcome, :string
    field :approval, :string
    field :feasibility, :string
    field :counter_unit, :string
    field :request, :string
  end

  @type t :: %__MODULE__{
          state: String.t(),
          phase: String.t(),
          tier: String.t(),
          outcome: String.t(),
          approval: String.t(),
          feasibility: String.t(),
          counter_unit: String.t(),
          request: String.t()
        }

  def phases,
    do:
      Lifecycle.states() |> Enum.map(&Lifecycle.phase/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  def approvals, do: [:recommended, :override_insufficient]
  def counter_units, do: ["optimization_items", "simulation_trials", "analysis_jobs"]

  defp enums do
    [
      state: Lifecycle.states(),
      phase: phases(),
      tier: Tier.all(),
      outcome: PilotOutcome.values(),
      approval: approvals(),
      feasibility: Keyword.fetch!(Definition.contract_meta().enum_values, :feasibility),
      counter_unit: counter_units(),
      request: StudyRequests.events()
    ]
  end

  def for_fields(fields) do
    values = Keyword.merge(Definition.contract_meta().enum_values, enums())

    selected =
      Enum.map(fields, fn
        {field, source} -> {field, Keyword.fetch!(values, source)}
        field -> {field, Keyword.fetch!(values, field)}
      end)

    %{enum_values: selected}
  end

  def contract_meta do
    enums = enums()

    %{
      enum_values: enums,
      runtime_values: [
        studyStates: constants(enums[:state]),
        studyPhases: constants(enums[:phase]),
        studyTiers: enums[:tier],
        studyOutcomes: constants(enums[:outcome]),
        studyApprovals: constants(enums[:approval]),
        studyFeasibility: constants(enums[:feasibility]),
        studyCounterUnits: constants(enums[:counter_unit]),
        studyRequests: constants(enums[:request]),
        studyProgression: Lifecycle.progression(),
        studyLifecycle: Map.new(Lifecycle.states(), &{&1, lifecycle(&1)})
      ]
    }
  end

  defp constants(values), do: Map.new(values, &{&1, &1})

  defp lifecycle(state) do
    %{
      canContinue: Lifecycle.active?(state),
      canCancel: Lifecycle.cancellable?(state),
      terminal: Lifecycle.terminal?(state),
      phase: Lifecycle.phase(state),
      attention: state in [:awaiting_final, :succeeded, :failed],
      restartable: state in [:failed, :cancelled],
      order: Enum.find_index(Lifecycle.progression(), &(&1 == state))
    }
  end

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
