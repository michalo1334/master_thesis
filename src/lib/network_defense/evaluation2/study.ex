defmodule NetworkDefense.Evaluation2.Study do
  @moduledoc """
  Supported public facade of native Evaluation2.

  Freeze YAML with `create_revision/1`, then pass its `Revision` to `start/1`.
  Keep the returned execution ID. `continue/2` drives caller-owned progression
  to explicit Pilot approval or a terminal state. `resume/2` freezes the approved
  counts; it does not grant approval implicitly through continuation.

  ```mermaid
  stateDiagram-v2
      [*] --> collecting_pilot
      collecting_pilot --> analyzing_pilot
      analyzing_pilot --> awaiting_final
      awaiting_final --> collecting_final: Explicit approval
      collecting_final --> analyzing_final
      analyzing_final --> succeeded: Atomic result acceptance
      collecting_pilot --> cancelled
      analyzing_pilot --> cancelled
      awaiting_final --> cancelled
      collecting_final --> cancelled
      analyzing_final --> cancelled
      collecting_pilot --> failed
      analyzing_pilot --> failed
      collecting_final --> failed
      analyzing_final --> failed
  ```

  Persistence owns transitions and canonical identities. Workflow owns one
  progression loop. Gust owns static phase tasks, retries and saved results.
  No background study coordinator advances phases without a continuation caller.

  Public values are `Revision`, `Status`, `PilotResult`, `Result` and bounded
  `Error`. They expose no private persistence row or Gust run ID. A successful
  result joins Pilot history, the frozen selection, the corrected native family
  and five measured timing triplets per tier. Intervals remain pointwise under
  the declared fixed-sample IID-input model.

  Authoring and browsing additions keep the same response shape. `definition_options/0`
  reports registered authoring values, `create_revision_from_params/1` freezes
  structured input through the YAML construction path, and `get_revision/1`,
  `list_revisions/1` and `list_executions/2` read frozen revisions and their
  execution history in bounded pages. A list entry exposes declared identities
  and compact accepted context, so no list read loads a stored report, result,
  timing or collection matrix.

  One frozen revision supports multiple executions with fresh physical effects.
  A finite wait leaves work active in a live application. Exit of the whole VM
  stops its workers and clock; lost incomplete measurements cannot be replaced.
  """

  use Spectral

  require Logger

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.DefinitionOptions
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Page
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Browsing
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2.Study.Persistence.Phase
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Progress
  alias NetworkDefense.Evaluation2.Study.ProgressSnapshot
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.RevisionDetail
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Evaluation2.Study.Workflow
  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @typedoc "Declared revision identity: study identifier and revision number."
  @type revision_ref :: Revision.t()

  @typedoc "Identifier of one study execution."
  @type execution_id :: Ecto.UUID.t()

  @typedoc "Identifier of one declared Pilot candidate."
  @type candidate_id :: PilotOutcome.candidate_id()

  @max_search_length 200
  @max_page_size Page.max_size()

  @typedoc "Optimization strategy of the existing optimization domain."
  @type strategy :: OptimizationParams.strategy()

  @typedoc "Approval intent: accept the recommendation or override an insufficient outcome."
  @type approval :: :recommended | {:override_insufficient, candidate_id()}

  @doc """
  Freeze one study revision from YAML text.

  Revision creation owns YAML/schema checks, declaration consistency and graph
  resolution. Unknown keys are dropped. Graph revisions and Host membership must
  resolve before insertion. Capacity, policies, bounds and scientific seeds are
  derived from the declared inputs. The configured environment label freezes
  here, so configure it before creation when Final collection is intended.

  This path and `create_revision_from_params/1` share one parse, resolve and
  insertion step, so equal declarations freeze equal definitions.
  """
  @spec create_revision(binary()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create_revision(document) when is_binary(document) do
    with {:ok, attrs} <- decode_yaml(document) do
      freeze(attrs)
    end
  end

  def create_revision(_document), do: {:error, invalid_yaml()}

  @doc """
  Freeze one study revision from structured authoring values.

  The input carries the declared settings of the definition input. The master
  seed arrives as a decimal string and becomes an exact integer before
  construction, so no browser number range limits it. Validation, graph
  resolution and freezing match the YAML path.

  """
  @spec create_revision_from_params(map()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create_revision_from_params(params) when is_map(params) do
    with {:ok, attrs} <- Definition.decode_params(params) do
      freeze(attrs)
    end
  end

  def create_revision_from_params(_params), do: {:error, invalid_params()}

  @doc """
  Return the authoring options of one new study revision.

  The options come from the registries that own the values, so the caller never
  declares a value that the application cannot construct. They describe the
  current application rather than a frozen revision.
  """
  @spec definition_options() :: {:ok, DefinitionOptions.t()} | {:error, Error.t()}
  def definition_options, do: {:ok, Views.definition_options()}

  @doc """
  Read one frozen revision with its authored settings.

  The detail reports the declared scientific settings, the frozen provenance
  and the derived study structure as separate values. A missing revision
  returns the bounded not-found error.
  """
  @spec get_revision(revision_ref()) :: {:ok, RevisionDetail.t()} | {:error, Error.t()}
  def get_revision(revision) do
    Persistence.fetch_revision(revision)
    |> bind(fn stored -> {:ok, Views.revision_detail(stored)} end)
  end

  @doc """
  List one bounded page of frozen revisions.

  The optional `:search` value matches the study name or declared identifier text. The
  request is an atom-keyed map with optional `:page` and `:page_size` values. Each entry
  reports its execution count and the state of its most recently changed
  execution, so a revision without executions reports `latest_state: nil`.
  """
  @spec list_revisions(map()) :: {:ok, Page.t()} | {:error, Error.t()}
  def list_revisions(params) do
    with {:ok, page} <- page_params(params),
         {:ok, search} <- search_text(Map.get(params, :search)) do
      Browsing.list_revisions(Map.put(page, :search, search))
      |> bind(fn stored -> {:ok, Views.page(stored, &Views.revision_summary/1)} end)
    end
  end

  @doc """
  List one bounded page of executions of one declared revision.

  The request is an atom-keyed map with optional `:page` and `:page_size`. A
  missing revision returns the bounded not-found error, and an existing revision
  without executions returns an empty page with `total: 0`. Each entry holds the
  accepted lifecycle state and the compact accepted context only.
  """
  @spec list_executions(revision_ref(), map()) ::
          {:ok, Page.t()} | {:error, Error.t()}
  def list_executions(revision, params) do
    with {:ok, request} <- page_params(params) do
      Browsing.list_executions(revision, request)
      |> bind(fn stored ->
        {:ok, Views.page(stored, &Views.execution_summary(stored.revision, &1))}
      end)
    end
  end

  defp freeze(attrs) do
    with {:ok, parsed} <- Definition.parse(attrs),
         {:ok, definition} <- Definition.resolve(parsed) do
      Persistence.insert_revision(definition)
      |> bind(fn revision -> {:ok, Views.revision(revision)} end)
    end
  end

  defp decode_yaml(document) do
    case YamlElixir.read_from_string(document) do
      {:ok, attrs} when is_map(attrs) -> {:ok, attrs}
      _ -> {:error, invalid_yaml()}
    end
  rescue
    YamlElixir.ParsingError -> {:error, invalid_yaml()}
  end

  defp invalid_yaml do
    Definition.Schema.error("invalid_yaml", [], "Supply one YAML definition object.")
  end

  defp invalid_params do
    Definition.Schema.error("invalid_definition", [], "Supply one structured definition object.")
  end

  defp page_params(params) when is_map(params) do
    if Enum.all?(Map.keys(params), &is_atom/1) do
      with {:ok, page} <- page_number(Map.get(params, :page, 1)),
           {:ok, size} <- page_size(Map.get(params, :page_size, Page.default_size())) do
        {:ok, %{page: page, page_size: size}}
      end
    else
      page_params(:invalid)
    end
  end

  defp page_params(_params),
    do: request_error("invalid_page_request", "Supply the list options as an atom-keyed map.")

  defp page_number(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp page_number(_value),
    do: request_error("invalid_page", "The page must be a positive integer.")

  defp page_size(value) when is_integer(value) and value in 1..@max_page_size,
    do: {:ok, value}

  defp page_size(value) when is_integer(value) and value > @max_page_size,
    do:
      request_error(
        "page_size_too_large",
        "The page size must not exceed #{@max_page_size}.",
        :request_too_large
      )

  defp page_size(_value),
    do: request_error("invalid_page_size", "The page size must be a positive integer.")

  defp search_text(nil), do: {:ok, nil}

  defp search_text(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      value ->
        if String.length(value) <= @max_search_length,
          do: {:ok, value},
          else:
            request_error(
              "search_too_long",
              "The search text must not exceed #{@max_search_length} characters.",
              :request_too_large
            )
    end
  end

  defp search_text(_text),
    do: request_error("invalid_search", "The search text must be a string.")

  defp request_error(code, message, category \\ :validation_failed) do
    {:error,
     %Error{category: category, issues: [%Error.Issue{code: code, path: [], message: message}]}}
  end

  @doc """
  Start one execution of a frozen revision.

  The new execution begins in Pilot collection. The execution transaction commits
  first, and the call then ensures its Pilot Collection Gust run.

  A failed provisioning keeps the committed execution: the call logs the bounded
  failure and returns the status, so the caller keeps the execution identifier
  for a later retry. The status is the refreshed row, or the last committed
  snapshot when that refresh fails.
  """
  @spec start(revision_ref()) :: {:ok, Status.t()} | {:error, Error.t()}
  def start(%Revision{} = revision) do
    case started_execution(revision) do
      {:ok, %{active_phase: %Phase{}} = context} ->
        ensure_collection(context)

      {:error, _failure} = failure ->
        failure
    end
  end

  @doc """
  Continue study execution to its supported approval or terminal boundary.

  Explicit approval freezes the Final counts. Continuation then completes the
  tier protocol and accepts the corrected family with its measured timings.

  A finite timeout returns current Status and leaves work active. This call
  grants no Final approval. Cancellation is observed through durable state.
  """
  @spec continue(execution_id(), keyword()) :: {:ok, Status.t()} | {:error, Error.t()}
  def continue(execution_id, opts \\ []), do: Workflow.continue(execution_id, opts)

  @doc """
  Read the lifecycle state of one execution.

  Status joins the execution row with its revision. Gust run detail stays
  internal.
  """
  @spec status(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def status(execution_id) do
    Persistence.fetch_execution(execution_id)
    |> bind(fn {execution, revision} -> {:ok, Views.status(revision, execution)} end)
  end

  @doc "Read scoped progress without advancing the execution."
  @spec progress(execution_id()) ::
          {:ok, ProgressSnapshot.t()} | {:error, Error.t()}
  def progress(execution_id), do: Progress.snapshot(execution_id)

  @doc """
  Read the complete Pilot report of one execution.

  The report holds the compact outcome and every candidate with its per
  comparison assessment. Approval uses this report, and an insufficient outcome
  is explained by it.
  """
  @spec pilot_result(execution_id()) :: {:ok, PilotResult.t()} | {:error, Error.t()}
  def pilot_result(execution_id) do
    with {:ok, {execution, revision}} <- Persistence.fetch_execution(execution_id),
         %PilotOutcome{} <- execution.pilot_outcome,
         {:ok, phase} <- Persistence.fetch_execution_phase(execution_id, :pilot_analysis),
         {:ok, phase_run} <- Persistence.fetch_phase_run(phase.id, :single),
         {:ok, output} <- Workflow.pilot_analysis_result(phase_run.id),
         true <- output.outcome == execution.pilot_outcome do
      Views.pilot_result(revision, output)
    else
      {:error, %Persistence.Error{} = failure} ->
        {:error, Views.error(failure)}

      {:error, %Error{}} = failure ->
        failure

      _not_accepted ->
        {:error,
         %Error{
           category: :validation_failed,
           issues: [
             %Error.Issue{
               code: "pilot_report_not_available",
               path: [],
               message: "The Pilot report has not been accepted."
             }
           ]
         }}
    end
  end

  @doc """
  Approve the Pilot outcome and freeze the Final selection.

  Resume resolves the declared candidate and freezes its two sample counts.
  An invalid approval leaves the execution waiting for approval. A valid approval
  ensures the first canonical Final tier run after committing the selection.
  """
  @spec resume(execution_id(), approval()) :: {:ok, Status.t()} | {:error, Error.t()}
  def resume(execution_id, approval) do
    Executions.accept_approval(execution_id, approval)
    |> bind(&ensure_collection/1)
  end

  @doc """
  Cancel one execution that is not terminal.

  Commit application cancellation before best-effort Gust stopping. Underlying
  effects can still finish, but late completion cannot advance terminal state.
  An already-terminal execution returns its existing Status unchanged.
  """
  @spec cancel(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def cancel(execution_id) do
    Executions.cancel_execution(execution_id)
    |> bind(fn context ->
      Workflow.stop(context.execution.id)
      {:ok, Views.status(context.revision, context.execution)}
    end)
  end

  @doc """
  Read the result of one successful execution.

  The result joins the execution-owned Pilot history with the Final-owned
  corrected family and measured timing. A read before success returns a bounded
  error.
  """
  @spec result(execution_id()) :: {:ok, Result.t()} | {:error, Error.t()}
  def result(execution_id) do
    Persistence.fetch_execution(execution_id)
    |> bind(fn {execution, revision} -> stored_result(execution, revision) end)
  end

  # The public result exists only for a successful execution.
  #
  # The success check happens before the immutable result is read, so the view
  # joins one successful execution with its own stored result.
  defp stored_result(%Persistence.Execution{state: :succeeded} = execution, revision) do
    Persistence.fetch_result(execution.id)
    |> bind(&Views.result(revision, execution, &1))
  end

  defp stored_result(_execution, _revision), do: {:error, Views.result_unavailable()}

  # Continue one storage step with the next step.
  #
  # A storage failure crosses the public boundary once, through the shared error
  # mapping of `Study.Views`.
  @spec bind(
          Persistence.response(value),
          (value -> {:ok, result} | {:error, Error.t()})
        ) :: {:ok, result} | {:error, Error.t()}
        when value: var, result: var
  defp bind(result, next) do
    case result do
      {:ok, value} -> next.(value)
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  # The committed execution keeps its state. Only the storage failure is mapped
  # into the bounded public error.
  @spec started_execution(revision_ref()) ::
          {:ok, Persistence.lifecycle_context()} | {:error, Error.t()}
  defp started_execution(revision) do
    case Executions.start_execution(revision) do
      {:ok, context} -> {:ok, context}
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  # The execution is committed, so a bounded provisioning failure becomes a logged
  # outcome and the caller still receives the execution identifier in the status.
  @spec ensure_collection(Persistence.lifecycle_context()) ::
          {:ok, Status.t()} | {:error, Error.t()}
  defp ensure_collection(context) do
    case Workflow.ensure_next_run(context.execution.id) do
      {:ok, _phase_run} ->
        status(context.execution.id)

      {:error, failure} ->
        Logger.error("Evaluation2 collection provisioning failed",
          error: inspect(failure)
        )

        refresh_or_committed_status(context)
    end
  end

  # A failed refresh must not hide the committed execution, so the committed
  # context becomes the returned status. It is the last committed snapshot.
  @spec refresh_or_committed_status(Persistence.lifecycle_context()) ::
          {:ok, Status.t()} | {:error, Error.t()}
  defp refresh_or_committed_status(context) do
    case status(context.execution.id) do
      {:ok, _status} = current ->
        current

      {:error, failure} ->
        Logger.error("Evaluation2 study status refresh failed", error: inspect(failure))
        {:ok, Views.status(context.revision, context.execution)}
    end
  end
end
