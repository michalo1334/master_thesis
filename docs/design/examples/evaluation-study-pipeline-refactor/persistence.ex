defmodule NetworkDefense.Evaluation.Study.Pipeline.StageAttempt do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "study_stage_attempts" do
    belongs_to(:execution, NetworkDefense.Evaluation.StudyExecution)

    field(:stage, Ecto.Enum,
      values: [:pilot_collection, :pilot_analysis, :final_collection, :final_analysis]
    )

    field(:status, Ecto.Enum, values: [:pending, :running, :succeeded, :failed, :cancelled])

    field(:accepted_reference, :map)
    field(:error, :map)

    has_many(:gust_runs, NetworkDefense.Evaluation.Study.Pipeline.StageGustRun)

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.StageGustRun do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "study_stage_gust_runs" do
    belongs_to(:stage_attempt, NetworkDefense.Evaluation.Study.Pipeline.StageAttempt)

    field(:position, :integer)
    field(:label, :string)
    field(:gust_run_id, :integer)

    timestamps(type: :utc_datetime_usec)
  end
end
