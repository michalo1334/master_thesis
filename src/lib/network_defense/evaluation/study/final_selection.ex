defmodule NetworkDefense.Evaluation.Study.FinalSelection do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Candidate
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyExecution

  @fields [:candidate_id, :plan_count_per_side, :attacks_per_plan, :pilot_override]
  @field_names Enum.map(@fields, &Atom.to_string/1)

  @primary_key false
  embedded_schema do
    field :candidate_id, :string
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
    field :pilot_override, :boolean
  end

  @type t :: %__MODULE__{
          candidate_id: String.t(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          pilot_override: boolean()
        }

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(selection, attrs) when is_map(attrs) do
    selection
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_length(:candidate_id, min: 1, max: 128)
    |> validate_number(:plan_count_per_side, greater_than: 0)
    |> validate_number(:attacks_per_plan, greater_than: 0)
    |> reject_unknown_fields(attrs)
  end

  @spec from_candidate(Candidate.t(), boolean()) :: {:ok, t()} | {:error, StudyError.t()}
  def from_candidate(%Candidate{} = candidate, pilot_override) when is_boolean(pilot_override) do
    materialize(
      %{
        candidate_id: candidate.id,
        plan_count_per_side: candidate.plan_count_per_side,
        attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: pilot_override
      },
      StudyError.final_selection_invalid()
    )
  end

  def from_candidate(_candidate, _pilot_override),
    do: {:error, StudyError.final_selection_invalid()}

  @spec from_execution(StudyExecution.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def from_execution(%StudyExecution{} = execution) do
    materialize(
      %{
        candidate_id: execution.selected_candidate_id,
        plan_count_per_side: execution.selected_plan_count_per_side,
        attacks_per_plan: execution.selected_attacks_per_plan,
        pilot_override: execution.pilot_override
      },
      StudyError.pilot_source_incomplete()
    )
  end

  @spec to_execution_attrs(t()) :: map()
  def to_execution_attrs(%__MODULE__{} = selection) do
    %{
      selected_candidate_id: selection.candidate_id,
      selected_plan_count_per_side: selection.plan_count_per_side,
      selected_attacks_per_plan: selection.attacks_per_plan,
      pilot_override: selection.pilot_override
    }
  end

  defp materialize(attrs, error) do
    case apply_action(changeset(%__MODULE__{}, attrs), :validate) do
      {:ok, %__MODULE__{} = selection} -> {:ok, selection}
      {:error, _changeset} -> {:error, error}
    end
  end

  defp reject_unknown_fields(changeset, attrs) do
    if Enum.any?(Map.keys(attrs), &(not known_field?(&1))) do
      add_error(changeset, :base, "contains unknown fields")
    else
      changeset
    end
  end

  defp known_field?(field) when field in @fields, do: true
  defp known_field?(field) when field in @field_names, do: true
  defp known_field?(_field), do: false
end
