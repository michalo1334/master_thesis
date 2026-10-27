defmodule NetworkDefense.Evaluation.StudyPhaseRun do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Evaluation.StudyPhase

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_phase_runs" do
    belongs_to :study_phase, StudyPhase, type: :binary_id
    field :tier, :string
    field :tier_position, :integer
    field :gust_run_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:study_phase_id, :tier, :tier_position, :gust_run_id])
    |> validate_required([:study_phase_id, :tier, :tier_position])
    |> validate_tier()
    |> validate_number(:tier_position, greater_than_or_equal_to: 0)
    |> validate_number(:gust_run_id, greater_than: 0)
    |> foreign_key_constraint(:study_phase_id)
    |> unique_constraint([:study_phase_id, :tier_position])
    |> unique_constraint([:study_phase_id, :tier])
    |> unique_constraint(:gust_run_id)
    |> check_constraint(:tier_position, name: :study_phase_runs_tier_position_check)
  end

  defp validate_tier(changeset) do
    case get_field(changeset, :tier) do
      tier when is_binary(tier) and tier != "" ->
        if String.trim(tier) == "" do
          add_error(changeset, :tier, "can't be blank")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
