defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Contracts.{
    PilotRequest,
    PilotResult
  }

  alias NetworkDefense.Evaluation.Study.Pipeline.ExecutionAccess
  alias NetworkDefense.Evaluation.Study.Revisions

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Outcome
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Work
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot.Contracts.Payload
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # In-process state of one Pilot analysis stage.
  #
  # The struct carries loaded domain values only. Gust tasks persist compact
  # identifiers and receipts, and each task reloads this IO from the persisted
  # run, so no large value crosses a task boundary.
  @phase :pilot_analysis

  @enforce_keys [:execution, :phase, :definition, :snapshot_id]
  defstruct [
    :execution,
    :phase,
    :definition,
    :snapshot_id,
    :snapshot,
    :payload,
    :request,
    :gust_run,
    :result,
    :outcome,
    candidates: []
  ]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          phase: StudyPhase.t(),
          definition: Definition.t(),
          snapshot_id: Ecto.UUID.t(),
          snapshot: EvidenceSnapshot.t() | nil,
          payload: Payload.t() | nil,
          request: PilotRequest.t() | nil,
          gust_run: Gust.Flows.Run.t() | nil,
          result: PilotResult.t() | nil,
          outcome: Outcome.t() | nil,
          candidates: [
            NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO.CandidateItem.t()
          ]
        }

  # One mapped candidate comparison. The canonical item is the persisted work
  # row; the result appears after the comparison returns.
  defmodule CandidateItem do
    @moduledoc false

    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Contracts.{
      CandidateComparisonResult,
      PilotRequest
    }

    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot.Contracts.Payload
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

    @enforce_keys [:item]
    defstruct [:item, :result, :request, :payload]

    @type t :: %__MODULE__{
            item: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Work.item(),
            result: CandidateComparisonResult.t() | nil,
            request: PilotRequest.t() | nil,
            payload: Payload.t() | nil
          }

    # The mapped task needs the authoritative request and payload, not a copy of
    # the phase IO.
    @spec values(t()) :: {:ok, PilotRequest.t(), Payload.t()} | {:error, PilotError.t()}
    def values(%__MODULE__{request: %PilotRequest{} = request, payload: %Payload{} = payload}),
      do: {:ok, request, payload}

    def values(%__MODULE__{}) do
      {:error, PilotError.incomplete_pilot("The mapped candidate item is not loaded.")}
    end
  end

  # Handoff from the accepted Pilot collection stage. The snapshot reference is
  # the only value that crosses the stage boundary.
  @spec from_collection(Collection.IO.t(), StudyPhase.t()) :: t()
  def from_collection(%Collection.IO{snapshot_id: snapshot_id} = io, %StudyPhase{} = phase)
      when is_binary(snapshot_id) do
    %__MODULE__{
      execution: io.execution,
      phase: phase,
      definition: io.definition,
      snapshot_id: snapshot_id
    }
  end

  # Loads the persisted run and every value the stage works on. The request is
  # decoded from run parameters, so a persisted pilot is never trusted blindly.
  @spec load_from_gust_run(integer()) :: {:ok, t()} | {:error, PilotError.t()}
  def load_from_gust_run(run_id) when is_integer(run_id) do
    %{params: params} = run = Gust.Flows.get_run!(run_id)

    with {:ok, request} <- PilotRequest.parse(params),
         {:ok, phase} <- analysis_phase(request),
         {:ok, execution} <- execution(phase),
         {:ok, definition} <- definition(execution),
         {:ok, stored_snapshot, payload} <- load_snapshot(request),
         :ok <- PilotRequest.matches_snapshot(request, stored_snapshot, payload) do
      {:ok,
       %__MODULE__{
         execution: execution,
         phase: phase,
         definition: definition,
         snapshot_id: request.snapshot_id,
         snapshot: stored_snapshot,
         payload: payload,
         request: request,
         gust_run: run
       }}
    end
  end

  # The stage needs the decoded request and the stored payload. A run that was
  # not hydrated cannot satisfy the analysis.
  @spec values(t()) :: {:ok, PilotRequest.t(), Payload.t()} | {:error, PilotError.t()}
  def values(%__MODULE__{request: %PilotRequest{} = request, payload: %Payload{} = payload}),
    do: {:ok, request, payload}

  def values(%__MODULE__{}) do
    {:error, PilotError.incomplete_pilot("The persisted pilot run is not loaded.")}
  end

  # The canonical candidate items for this stage. Every item is recomputed from
  # the declared request and the stored payload before any mapped task exists.
  @spec candidates(t()) :: {:ok, [CandidateItem.t()]} | {:error, PilotError.t()}
  def candidates(%__MODULE__{} = io) do
    with {:ok, request, payload} <- values(io),
         :ok <- Work.preflight(request, payload),
         {:ok, items} <- Work.canonical_items(request, payload) do
      {:ok, Enum.map(items, &%CandidateItem{item: &1})}
    end
  end

  # The authoritative canonical item for one mapped task. The persisted item
  # must equal the row recomputed from the declared request and the snapshot.
  @spec candidate(t(), term()) :: {:ok, CandidateItem.t()} | {:error, PilotError.t()}
  def candidate(
        %__MODULE__{request: %PilotRequest{} = request, payload: %Payload{} = payload},
        item
      ) do
    with {:ok, items} <- Work.canonical_items(request, payload),
         {:ok, expected} <- locate(items, item, length(request.expected_comparisons)) do
      {:ok, %CandidateItem{item: expected, request: request, payload: payload}}
    end
  end

  defp locate(items, item, comparison_count) do
    with {:ok, candidate_position} <- position(item["candidate_position"]),
         {:ok, comparison_position} <- position(item["comparison_position"]),
         index = candidate_position * comparison_count + comparison_position,
         %{} = expected <- Enum.at(items, index) do
      if expected == item do
        {:ok, expected}
      else
        {:error, PilotError.changed_candidate_result("A persisted pilot work item changed.")}
      end
    else
      nil -> {:error, PilotError.incomplete_pilot("A mapped work item has no canonical row.")}
      :error -> {:error, PilotError.incomplete_pilot("A mapped work item position is invalid.")}
      {:error, %PilotError{} = error} -> {:error, error}
    end
  end

  defp position(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp position(_value), do: :error

  defp analysis_phase(%PilotRequest{pilot_id: pilot_id}) do
    case Repo.get_by(StudyPhase, execution_id: pilot_id, phase: @phase) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, PilotError.incomplete_pilot("The pilot analysis phase is missing.")}
    end
  rescue
    _invalid -> {:error, PilotError.incomplete_pilot("The pilot run has no study phase.")}
  end

  defp execution(%StudyPhase{execution_id: execution_id}) do
    case ExecutionAccess.fetch_trusted(execution_id) do
      {:ok, %StudyExecution{} = execution} -> {:ok, execution}
      {:error, %StudyError{} = error} -> {:error, bounded(error)}
    end
  end

  defp definition(%StudyExecution{study_revision_id: revision_id}) do
    case Revisions.load_definition(revision_id) do
      {:ok, %Definition{} = definition} -> {:ok, definition}
      {:error, %StudyError{} = error} -> {:error, bounded(error)}
    end
  end

  defp load_snapshot(%PilotRequest{snapshot_id: snapshot_id}) do
    # The snapshot loader reports Pilot errors only, so this branch stays bounded
    # without a study-error fallback.
    case EvidenceSnapshots.load(snapshot_id) do
      {:ok, %EvidenceSnapshot{} = snapshot, %Payload{} = payload} -> {:ok, snapshot, payload}
      {:error, %PilotError{} = error} -> {:error, error}
    end
  end

  # The stage reports Pilot errors. A study-level failure is a broken persisted
  # pilot, and it stays bounded inside the pilot boundary.
  defp bounded(%StudyError{}),
    do: PilotError.incomplete_pilot("The persisted pilot state is not complete.")
end
