defmodule NetworkDefense.Evaluation2.Study.Persistence.PhaseRun do
  @moduledoc false

  # Link between one study phase and one Gust run.
  #
  # Every Gust run has one phase-run record. Single-run phases use the `:single`
  # key, and Final collection uses one tier key per declared tier. The linking
  # caller supplies the primary key, because the same UUID is the phase-run
  # identity inside the Gust run input.
  #
  # Gust owns run status, task status, task results, and task errors. This record
  # keeps the application-to-Gust link only. `gust_run_id` has no SQL foreign key
  # because the Gust table might not exist when this schema is created.

  use Ecto.Schema

  alias NetworkDefense.Evaluation2.Study.Tier

  @run_keys [:single | Tier.all()]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Run key of one phase run: the single phase run or one declared tier."
  @type run_key :: :single | Tier.t()

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_id: Ecto.UUID.t(),
          run_key: run_key(),
          gust_run_id: pos_integer(),
          inserted_at: DateTime.t()
        }

  schema "evaluation2_study_phase_runs" do
    field :study_phase_id, :binary_id
    field :run_key, Ecto.Enum, values: @run_keys
    field :gust_run_id, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
