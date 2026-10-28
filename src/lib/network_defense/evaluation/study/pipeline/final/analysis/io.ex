defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Planner
  alias NetworkDefense.Evaluation.Study.Pipeline.ExecutionAccess
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Binding
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Request
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Result
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Handoff
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Member
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.RequestBuilder
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Snapshot.Contracts.Payload
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TierRuns
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.TimingSummary
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError
  alias NetworkDefense.Evaluation.Study.Pipeline.Result, as: CompactResult
  alias NetworkDefense.Evaluation.Study.Revisions
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Repo

  # In-process state of one Final analysis stage.
  #
  # The struct carries loaded domain values only. Gust tasks persist compact
  # identifiers and receipts, and each task reloads this IO from the persisted
  # run, so no large value crosses a task boundary.
  #
  # Collection acceptance and both loaders describe the same contract: the
  # execution, the Final analysis phase, the definition, the accepted snapshot,
  # the declared tiers with their stored runs, and the persisted timing summary.
  # A loader adds the typed request, the snapshot payload, and the Gust run it
  # was hydrated from.
  @phase :final_analysis
  @collection_phase :final_collection

  @enforce_keys [:execution, :phase, :definition, :snapshot_id, :timing]
  defstruct [
    :execution,
    :phase,
    :definition,
    :snapshot_id,
    :timing,
    :payload,
    :request,
    :gust_run,
    :result,
    :compact_result,
    tiers: [],
    runs: [],
    comparisons: []
  ]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          phase: StudyPhase.t(),
          definition: Definition.t(),
          snapshot_id: Ecto.UUID.t(),
          tiers: [String.t()],
          runs: [NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO.TierRun.t()],
          timing: TimingSummary.t(),
          payload: Payload.t() | nil,
          request: Request.t() | nil,
          gust_run: Gust.Flows.Run.t() | nil,
          result: Result.t() | nil,
          compact_result: CompactResult.t() | nil,
          comparisons: [
            NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO.ComparisonItem.t()
          ]
        }

  # One collected tier, in declared order. The reference stays compact: the
  # stored Gust run owns the task history.
  defmodule TierRun do
    @moduledoc false

    @enforce_keys [:tier, :tier_position, :gust_run_id]
    defstruct [:tier, :tier_position, :gust_run_id]

    @type t :: %__MODULE__{
            tier: String.t(),
            tier_position: non_neg_integer(),
            gust_run_id: pos_integer()
          }
  end

  # One mapped comparison. `item` is the compact persisted argument, so a task
  # can compare it with the stored Gust params without decoding it twice.
  #
  # The comparison request comes from the stored snapshot and the submitted
  # seed. The typed result appears after the comparison returns.
  defmodule ComparisonItem do
    @moduledoc false

    alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Request
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Member
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Snapshot.Contracts.Payload
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError

    @enforce_keys [:item]
    defstruct [:item, :request, :payload, :comparison_request, :result]

    @type t :: %__MODULE__{
            item: map(),
            request: Request.t() | nil,
            payload: Payload.t() | nil,
            comparison_request: ComparisonRequest.t() | nil,
            result: Member.result() | nil
          }

    # The mapped task needs the authoritative request and payload, not a copy of
    # the phase IO.
    @spec values(t()) :: {:ok, Request.t(), Payload.t()} | {:error, FinalError.t()}
    def values(%__MODULE__{request: %Request{} = request, payload: %Payload{} = payload}),
      do: {:ok, request, payload}

    def values(%__MODULE__{}) do
      {:error, FinalError.incomplete_family("The mapped Final comparison is not loaded.")}
    end
  end

  # Restart loading of one accepted Final analysis.
  #
  # The execution must already be analyzing, so a resumed stage reuses the
  # accepted run and the persisted handoff instead of starting a second analysis.
  @spec load(term()) :: {:ok, t()} | {:error, StudyError.t()}
  def load(execution_id) do
    with {:ok, execution} <- analyzing_execution(execution_id),
         {:ok, request} <- request(execution) do
      hydrate(request, nil)
    end
  end

  # The stage needs the decoded request and the stored payload. A run that was
  # not hydrated cannot satisfy the analysis.
  @spec values(t()) :: {:ok, Request.t(), Payload.t()} | {:error, FinalError.t()}
  def values(%__MODULE__{request: %Request{} = request, payload: %Payload{} = payload}),
    do: {:ok, request, payload}

  def values(%__MODULE__{}) do
    {:error, FinalError.incomplete_family("The persisted Final run is not loaded.")}
  end

  # Loads the persisted run and every value the stage works on. The request is
  # decoded from run parameters and bound to the stored snapshot, so a persisted
  # Final request is never trusted blindly.
  @spec load_from_gust_run(integer()) :: {:ok, t()} | {:error, FinalError.t()}
  def load_from_gust_run(run_id) when is_integer(run_id) do
    %{params: params} = run = Gust.Flows.get_run!(run_id)

    case Request.parse(params) do
      {:ok, request} ->
        case hydrate(request, run) do
          {:ok, io} -> {:ok, io}
          {:error, %StudyError{}} -> {:error, as_final_error()}
        end

      {:error, %FinalError{} = error} ->
        {:error, error}
    end
  end

  # The declared comparison items for this stage. Every item is rebuilt from the
  # declared request and the stored snapshot before any mapped task exists.
  @spec comparisons(t()) :: {:ok, [ComparisonItem.t()]} | {:error, FinalError.t()}
  def comparisons(%__MODULE__{} = io) do
    with {:ok, request, payload} <- values(io),
         :ok <- Member.preflight(request, payload) do
      build_comparisons(request, payload, request.expected_comparisons)
    end
  end

  # The authoritative comparison item for one mapped task. The persisted item
  # must hold its declared position and its declared identity.
  @spec comparison(t(), term()) :: {:ok, ComparisonItem.t()} | {:error, FinalError.t()}
  def comparison(
        %__MODULE__{request: %Request{} = request, payload: %Payload{} = payload},
        item
      ) do
    with {:ok, parsed} <- Member.parse_item(item),
         :ok <- declared_item(request, parsed),
         {:ok, comparison_request} <- Member.comparison_request(request, payload, parsed.position) do
      {:ok,
       %ComparisonItem{
         item: item,
         request: request,
         payload: payload,
         comparison_request: comparison_request
       }}
    end
  end

  def comparison(%__MODULE__{}, _item) do
    {:error, FinalError.incomplete_family("The persisted Final run is not loaded.")}
  end

  # One IO from the persisted Final state. Both the restart loader and the task
  # loader go through this function, so they agree on every identity.
  defp hydrate(%Request{} = request, gust_run) do
    with {:ok, execution} <- execution(request.study_execution_id),
         {:ok, analysis_phase} <- stored_phase(execution, @phase),
         :ok <- empty_analysis(analysis_phase),
         {:ok, collection_phase} <- stored_phase(execution, @collection_phase),
         {:ok, snapshot_id} <- snapshot(collection_phase),
         :ok <- same_snapshot(request, snapshot_id),
         {:ok, definition} <- definition(execution),
         {:ok, tiers} <- tiers(definition),
         {:ok, handoff} <- handoff(collection_phase, tiers),
         {:ok, payload} <- verified_payload(request) do
      {:ok,
       %__MODULE__{
         execution: execution,
         phase: analysis_phase,
         definition: definition,
         snapshot_id: snapshot_id,
         tiers: handoff.tiers,
         runs: tier_runs(handoff),
         timing: handoff.timing,
         payload: payload,
         request: request,
         gust_run: gust_run
       }}
    end
  end

  defp build_comparisons(%Request{} = request, %Payload{} = payload, declared) do
    declared
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {identity, position}, {:ok, acc} ->
      case declared_comparison(request, payload, position, identity) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, %FinalError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  defp declared_comparison(%Request{} = request, %Payload{} = payload, position, identity) do
    item = Member.item_params(position, identity)

    with {:ok, _parsed} <- Member.parse_item(item),
         {:ok, comparison_request} <- Member.comparison_request(request, payload, position) do
      {:ok,
       %ComparisonItem{
         item: item,
         request: request,
         payload: payload,
         comparison_request: comparison_request
       }}
    end
  end

  defp declared_item(%Request{} = request, %{position: position, identity: identity}) do
    case Enum.at(request.expected_comparisons, position) do
      %Identity{} = declared ->
        if Identity.matches?(identity, declared) do
          :ok
        else
          {:error,
           FinalError.changed_member("A mapped Final member does not hold its declared identity.")}
        end

      nil ->
        {:error,
         FinalError.incomplete_family("A Final member has no declared comparison position.")}
    end
  end

  defp reverse({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse({:error, %FinalError{} = error}), do: {:error, error}

  defp analyzing_execution(execution_id) do
    case ExecutionAccess.fetch_trusted(execution_id) do
      {:ok, %StudyExecution{state: :analyzing_final} = execution} ->
        {:ok, execution}

      {:ok, %StudyExecution{}} ->
        {:error, StudyError.final_analysis_failed()}

      {:error, %StudyError{} = error} ->
        {:error, error}
    end
  rescue
    _invalid -> {:error, StudyError.study_execution_not_found()}
  end

  defp execution(execution_id) do
    case ExecutionAccess.fetch_trusted(execution_id) do
      {:ok, %StudyExecution{} = execution} -> {:ok, execution}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  rescue
    _invalid -> {:error, StudyError.study_execution_not_found()}
  end

  defp stored_phase(%StudyExecution{id: execution_id}, name) do
    case Repo.get_by(StudyPhase, execution_id: execution_id, phase: name) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  # An accepted analysis has no stored result yet: the result arrives with the
  # completion transition, so a phase that already holds one cannot be resumed.
  defp empty_analysis(%StudyPhase{error: nil, result_ref: nil}), do: :ok

  defp empty_analysis(%StudyPhase{}), do: {:error, StudyError.invalid_study_phase()}

  defp snapshot(%StudyPhase{snapshot_id: snapshot_id, error: nil}) do
    case Ecto.UUID.cast(snapshot_id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp snapshot(%StudyPhase{}), do: {:error, StudyError.invalid_study_phase()}

  defp same_snapshot(%Request{snapshot_id: snapshot_id}, snapshot_id), do: :ok

  defp same_snapshot(%Request{}, _snapshot_id),
    do: {:error, StudyError.final_analysis_failed()}

  defp definition(%StudyExecution{study_revision_id: revision_id}) do
    case Revisions.load_definition(revision_id) do
      {:ok, %Definition{} = definition} -> {:ok, definition}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp tiers(%Definition{} = definition) do
    case Planner.tier_order(definition) do
      {:ok, tiers} -> {:ok, tiers}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  # The handoff is the only persisted source of the collected ranks and timings.
  # It must describe the declared tiers and the stored tier runs exactly.
  defp handoff(%StudyPhase{id: phase_id, result_ref: result_ref}, tiers) do
    with {:ok, %Handoff{} = handoff} <- parsed_handoff(result_ref),
         true <- handoff.tiers == tiers,
         {:ok, rows} <- ordered_tier_runs(phase_id),
         true <- Handoff.matches_runs?(handoff, rows) do
      {:ok, handoff}
    else
      false -> {:error, StudyError.incomplete_final_family()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp parsed_handoff(result_ref) do
    case Handoff.parse(result_ref) do
      {:ok, %Handoff{} = handoff} -> {:ok, handoff}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp ordered_tier_runs(phase_id) do
    case TierRuns.ordered_for_phase(phase_id) do
      {:ok, rows} -> {:ok, rows}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp tier_runs(%Handoff{runs: runs}) do
    Enum.map(runs, fn run ->
      %TierRun{
        tier: run.tier,
        tier_position: run.tier_position,
        gust_run_id: run.gust_run_id
      }
    end)
  end

  defp request(%StudyExecution{} = execution) do
    with {:ok, %StudyPhase{} = collection_phase} <- stored_phase(execution, @collection_phase),
         {:ok, snapshot_id} <- snapshot(collection_phase) do
      case RequestBuilder.build(execution.id, snapshot_id) do
        {:ok, %Request{} = request} -> {:ok, request}
        {:error, %FinalError{}} -> {:error, StudyError.final_analysis_failed()}
      end
    end
  end

  defp verified_payload(%Request{} = request) do
    case Binding.verify(request) do
      {:ok, %Payload{} = payload} -> {:ok, payload}
      {:error, %FinalError{}} -> {:error, StudyError.final_analysis_failed()}
    end
  end

  # A Gust task boundary reports Final errors, so one study-level failure of the
  # persisted state becomes one bounded Final error.
  defp as_final_error do
    FinalError.incomplete_family("The persisted Final state is not complete.")
  end
end
