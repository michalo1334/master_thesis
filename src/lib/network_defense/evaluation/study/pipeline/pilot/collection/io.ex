defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.{ExecutionAccess, Revisions}
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.WorkItem
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # In-process state of one Pilot collection stage.
  #
  # Gust tasks persist only compact identifiers and receipts. Each task reloads
  # this IO from the persisted run, so no large value crosses a task boundary.
  @phase :pilot_collection
  @active_state :collecting_pilot
  @terminal_states [:awaiting_final, :succeeded, :failed, :cancelled]

  @enforce_keys [:execution, :phase, :definition]
  defstruct [:execution, :phase, :definition, :gust_run, :snapshot_id, work: [], items: []]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          phase: StudyPhase.t(),
          definition: Definition.t(),
          gust_run: Gust.Flows.Run.t() | nil,
          snapshot_id: Ecto.UUID.t() | nil,
          work: [WorkItem.t()],
          items: [Item.t()]
        }

  @spec load(term()) :: {:ok, t()} | {:error, StudyError.t()} | {:stop, atom()}
  def load(execution_id) do
    with {:ok, execution} <- ExecutionAccess.fetch(execution_id),
         :ok <- active?(execution),
         {:ok, phase} <- collection_phase(execution),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id) do
      {:ok, %__MODULE__{execution: execution, phase: phase, definition: definition}}
    end
  end

  @spec load_from_gust_run(integer()) :: {:ok, t()} | {:error, StudyError.t()}
  def load_from_gust_run(run_id) when is_integer(run_id) do
    run_id |> Gust.Flows.get_run!() |> from_run()
  end

  # One mapped collection item. Only the stable identifier crosses Gust.
  defmodule Item do
    @moduledoc false

    @enforce_keys [:collection_item_id]
    defstruct [:collection_item_id, :receipt]

    @type t :: %__MODULE__{
            collection_item_id: Ecto.UUID.t(),
            receipt: term() | nil
          }
  end

  defp from_run(%{params: %{"study_phase_id" => phase_id}} = run) do
    with {:ok, id} <- Ecto.UUID.cast(phase_id),
         %StudyPhase{} = phase <- Repo.get(StudyPhase, id),
         {:ok, execution} <- ExecutionAccess.fetch_trusted(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id) do
      {:ok,
       %__MODULE__{
         execution: execution,
         phase: phase,
         definition: definition,
         gust_run: run
       }}
    else
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp from_run(_run), do: {:error, StudyError.invalid_study_phase()}

  defp active?(%StudyExecution{state: @active_state}), do: :ok

  defp active?(%StudyExecution{state: state}) when state in @terminal_states, do: {:stop, state}

  defp active?(%StudyExecution{}), do: {:error, StudyError.study_execution_not_found()}

  defp collection_phase(%StudyExecution{id: execution_id}) do
    case Repo.get_by(StudyPhase, execution_id: execution_id, phase: @phase) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end
end
