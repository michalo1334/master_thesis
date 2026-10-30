defmodule NetworkDefense.Evaluation2.Study.Persistence.Result do
  @moduledoc false

  # Stored result of one successful execution.
  #
  # The record keeps the Final-owned corrected family and the raw measured
  # timing. Pilot outcome, selection, and revision stay on the successful
  # execution, so the supported result view joins both records.
  #
  # Reporting reads this record instead of rebuilding domain history. Both JSONB
  # values decode back into their typed shapes at the persistence boundary.

  use Ecto.Schema

  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Result.Timing

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_execution_id: Ecto.UUID.t(),
          family: CorrectedFamily.t(),
          timing: Timing.t(),
          inserted_at: DateTime.t()
        }

  schema "evaluation2_study_results" do
    field :study_execution_id, :binary_id
    field :family, :map
    field :timing, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
