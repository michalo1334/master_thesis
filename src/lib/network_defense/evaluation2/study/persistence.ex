defmodule NetworkDefense.Evaluation2.Study.Persistence do
  @moduledoc """
  Storage boundary of the frozen revision, the joined record contexts, the
  canonical phase-run link, the phase-owned evidence snapshot, and the stored
  result.

  A phase run is the only application record of one Gust run. The linking
  caller supplies the phase-run identity, so the identity exists before the Gust
  run and travels inside the run input. `(study_phase_id, run_key)` and
  `gust_run_id` are unique, so concurrent linkers converge on one canonical row.

  Lifecycle commands belong to `Persistence.Executions`, and collection plans,
  items, and effect reservations belong to `Persistence.Collection`. Both
  owners call the shared helpers at the end of this module, so the transaction,
  containment, codec, and identifier rules stay in one place.

  This module touches application tables only. Gust run status, tasks, and
  results belong to `NetworkDefense.Evaluation2.Study.Workflow`.

  ```mermaid
  flowchart TB
      Persistence[Persistence shared storage rules] --> Executions[Executions: lifecycle transactions]
      Persistence --> Collection[Collection: plan and reservation transactions]
      Persistence --> Links[Revision, phase-run and snapshot ownership]
      Executions --> Result[Atomic result and success]
      Collection --> Effects[Unique item effect links]
  ```

  Snapshot insertion prepares evidence. Lifecycle acceptance and its successor
  phase are separate durable facts. Public reads expose transient Study values,
  rather than these internal storage records.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error, as: StudyError
  alias NetworkDefense.Evaluation2.Study.Evidence
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Persistence.Error
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Persistence.Execution
  alias NetworkDefense.Evaluation2.Study.Persistence.Phase
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Persistence.Result
  alias NetworkDefense.Evaluation2.Study.Persistence.Revision
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Revision, as: RevisionIdentity
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Repo

  @typedoc "Tagged result of one persistence operation."
  @type response(value) :: {:ok, value} | {:error, Error.t()}

  @typedoc "Current lifecycle authority of one execution."
  @type lifecycle_context :: %{
          execution: Execution.t(),
          revision: Revision.t(),
          active_phase: Phase.t() | nil
        }

  @typedoc "One phase with its owning execution and frozen revision."
  @type phase_context :: %{
          phase: Phase.t(),
          execution: Execution.t(),
          revision: Revision.t()
        }

  @typedoc "One phase run with its complete owning chain."
  @type phase_run_context :: %{
          phase_run: PhaseRun.t(),
          phase: Phase.t(),
          execution: Execution.t(),
          revision: Revision.t()
        }

  @typedoc "One stored evidence snapshot with its complete owning chain."
  @type evidence_context :: %{
          snapshot: EvidenceSnapshot.t(),
          phase: Phase.t(),
          execution: Execution.t(),
          revision: Revision.t()
        }

  @typedoc "Declared revision identity of one frozen revision."
  @type revision_ref :: RevisionIdentity.t()

  # --- revisions ---------------------------------------------------------

  # Creation is the one external check point: `Study` parses the document and
  # resolves the declared graph references before it calls this function. Equal
  # repeated insertion returns the stored revision, and the same declared
  # identity with different content returns `:conflict`.
  @doc "Store a resolved immutable definition under its declared study/revision identity."
  @spec insert_revision(Definition.t()) :: response(Revision.t())
  def insert_revision(%Definition{} = definition) do
    with {:ok, identity} <- declared_identity(definition),
         {:ok, params} <- encode_json(Definition, :t, definition, :insert_revision, :definition) do
      contain(:insert_revision, :revision, fn ->
        insert_revision_once(identity, definition, params)
      end)
    end
  end

  @spec fetch_revision(revision_ref()) :: response(Revision.t())
  def fetch_revision(revision_ref) do
    with {:ok, identity} <- cast_identity(revision_ref, :fetch_revision) do
      fetch_one(:fetch_revision, :revision, revision_query(identity), fn row ->
        decode_revision(row, :fetch_revision)
      end)
    end
  end

  defp declared_identity(%Definition{study: %{id: study_id, revision: revision}})
       when is_binary(study_id) and is_integer(revision) and revision > 0 do
    {:ok, %{study_id: study_id, revision: revision}}
  end

  defp declared_identity(%Definition{}) do
    {:error, error(:storage, :insert_revision, :revision, :invalid_identity)}
  end

  defp revision_query(%{study_id: study_id, revision: revision}) do
    from r in Revision, where: r.study_id == ^study_id and r.revision == ^revision
  end

  defp insert_revision_once(identity, definition, params) do
    %Revision{}
    |> Changeset.change(Map.put(identity, :definition, params))
    |> Changeset.unique_constraint(:revision,
      name: :evaluation2_study_revisions_study_id_revision_index
    )
    |> Repo.insert()
    |> case do
      {:ok, row} -> decode_revision(row, :insert_revision)
      {:error, changeset} -> stored_revision_result(changeset, identity, definition)
    end
  end

  defp stored_revision_result(changeset, identity, definition) do
    if unique_conflict?(changeset) do
      compare_stored_revision(identity, definition)
    else
      {:error, error(:storage, :insert_revision, :revision, changeset)}
    end
  end

  # An accepted definition is immutable, so an equal decoded value is the stored
  # revision and a different one is a conflict.
  defp compare_stored_revision(identity, definition) do
    case Repo.one(revision_query(identity)) do
      nil -> {:error, error(:storage, :insert_revision, :revision, :missing_after_conflict)}
      row -> compare_revision_definition(row, definition)
    end
  end

  defp compare_revision_definition(row, definition) do
    with {:ok, stored} <- decode_revision(row, :insert_revision) do
      if stored.definition == definition do
        {:ok, stored}
      else
        {:error, error(:conflict, :insert_revision, :revision, :different_definition)}
      end
    end
  end

  # --- execution reads ---------------------------------------------------

  # A status view needs the execution row and the revision it runs, so both come
  # from one joined query.
  @spec fetch_execution(Ecto.UUID.t()) :: response({Execution.t(), Revision.t()})
  def fetch_execution(execution_id) do
    with {:ok, uuid} <- cast_id(execution_id, :fetch_execution, :execution) do
      query =
        from e in Execution,
          join: r in Revision,
          on: r.id == e.study_revision_id,
          where: e.id == ^uuid,
          select: {e, r}

      fetch_one(:fetch_execution, :execution, query, &decode_chain(&1, :fetch_execution))
    end
  end

  # --- stored results ----------------------------------------------------

  # A successful execution owns its result. A successful execution without one is
  # an internal invariant failure, and a non-successful execution has no result to
  # report.
  @spec fetch_result(Ecto.UUID.t()) :: response(Result.t())
  def fetch_result(execution_id) do
    with {:ok, uuid} <- cast_id(execution_id, :fetch_result, :execution) do
      query =
        from e in Execution,
          left_join: r in Result,
          on: r.study_execution_id == e.id,
          where: e.id == ^uuid,
          select: {e.state, r}

      fetch_one(:fetch_result, :execution, query, &result_row(&1, :fetch_result))
    end
  end

  defp result_row({_state, %Result{} = result}, operation), do: decode_result(result, operation)

  defp result_row({:succeeded, nil}, operation) do
    {:error, error(:storage, operation, :result, :missing_result)}
  end

  defp result_row({_state, nil}, operation) do
    {:error, error(:not_found, operation, :result, nil)}
  end

  # --- phases and phase runs ---------------------------------------------

  @spec fetch_execution_phase(Ecto.UUID.t(), Phase.phase_kind()) :: response(Phase.t())
  def fetch_execution_phase(execution_id, kind) do
    with {:ok, uuid} <- cast_id(execution_id, :fetch_execution_phase, :execution) do
      query = from p in Phase, where: p.study_execution_id == ^uuid and p.phase == ^kind
      fetch_one(:fetch_execution_phase, :phase, query, &{:ok, &1})
    end
  end

  @spec fetch_phase_context(Ecto.UUID.t()) :: response(phase_context())
  def fetch_phase_context(phase_id) do
    with {:ok, uuid} <- cast_id(phase_id, :fetch_phase_context, :phase) do
      query =
        from p in Phase,
          join: e in Execution,
          on: e.id == p.study_execution_id,
          join: r in Revision,
          on: r.id == e.study_revision_id,
          where: p.id == ^uuid,
          select: {p, e, r}

      fetch_one(:fetch_phase_context, :phase, query, fn row ->
        build_phase_context(row, :fetch_phase_context)
      end)
    end
  end

  @spec fetch_phase_run_context(Ecto.UUID.t()) :: response(phase_run_context())
  def fetch_phase_run_context(phase_run_id) do
    with {:ok, uuid} <- cast_id(phase_run_id, :fetch_phase_run_context, :phase_run) do
      fetch_one(:fetch_phase_run_context, :phase_run, phase_run_chain_query(uuid), fn row ->
        build_phase_run_context(row, :fetch_phase_run_context)
      end)
    end
  end

  @spec fetch_phase_run(Ecto.UUID.t(), PhaseRun.run_key()) :: response(PhaseRun.t())
  def fetch_phase_run(phase_id, run_key) do
    with {:ok, uuid} <- cast_id(phase_id, :fetch_phase_run, :phase) do
      fetch_one(:fetch_phase_run, :phase_run, phase_run_query(uuid, run_key), &{:ok, &1})
    end
  end

  @spec list_phase_runs(Ecto.UUID.t()) :: response([PhaseRun.t()])
  def list_phase_runs(phase_id) do
    with {:ok, uuid} <- cast_id(phase_id, :list_phase_runs, :phase) do
      read(:list_phase_runs, :phase_run, fn -> Repo.all(phase_runs_query(uuid)) end)
    end
  end

  # The canonical row decides which undispatched Gust run may be dispatched, so a
  # concurrent loser receives the stored row instead of a second link.
  @doc """
  Link one Gust run to one phase run key.

  The caller supplies the phase-run identity, because the same identity is part
  of the Gust run input. When `(phase_id, run_key)` is already linked, the
  stored canonical row is returned and `gust_run_id` is ignored, so the caller
  discards its losing Gust run. A Gust run that another phase run already owns
  reports `:conflict`.
  """
  @spec link_phase_run(Ecto.UUID.t(), PhaseRun.run_key(), Ecto.UUID.t(), integer()) ::
          response(PhaseRun.t())
  def link_phase_run(phase_id, run_key, proposed_phase_run_id, gust_run_id) do
    with {:ok, uuid} <- cast_id(phase_id, :link_phase_run, :phase),
         {:ok, proposed_id} <- cast_id(proposed_phase_run_id, :link_phase_run, :phase_run) do
      tx(:link_phase_run, :phase_run, fn ->
        linked_phase_run(uuid, run_key, proposed_id, gust_run_id, :link_phase_run)
      end)
    end
  end

  defp linked_phase_run(phase_id, run_key, proposed_id, gust_run_id, operation) do
    with {:ok, initial} <- stored_phase(phase_id, operation),
         {:ok, execution} <- lock_link_execution(initial.study_execution_id, operation),
         {:ok, phase} <- lock_phase(phase_id, operation) do
      link_run_once(phase, execution.state, run_key, proposed_id, gust_run_id, operation)
    end
  end

  defp lock_link_execution(execution_id, operation) do
    query = from e in Execution, where: e.id == ^execution_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, error(:not_found, operation, :execution, nil)}
      execution -> {:ok, execution}
    end
  end

  defp phase_run_query(phase_id, run_key) do
    from pr in PhaseRun, where: pr.study_phase_id == ^phase_id and pr.run_key == ^run_key
  end

  defp phase_runs_query(phase_id) do
    from pr in PhaseRun,
      where: pr.study_phase_id == ^phase_id,
      order_by: [asc: pr.inserted_at, asc: pr.id]
  end

  # The phase row lock serializes two linkers, so the loser reads the canonical
  # row instead of provoking a constraint error inside its transaction.
  defp link_run_once(phase, state, run_key, proposed_id, gust_run_id, operation) do
    case Repo.get_by(PhaseRun, study_phase_id: phase.id, run_key: run_key) do
      %PhaseRun{} = phase_run ->
        {:ok, phase_run}

      nil ->
        if Lifecycle.phase(state) == phase.phase do
          insert_phase_run(phase.id, run_key, proposed_id, gust_run_id)
        else
          {:error, error(:conflict, operation, :phase_run, :inactive_phase)}
        end
    end
  end

  defp insert_phase_run(phase_id, run_key, proposed_id, gust_run_id) do
    %PhaseRun{
      id: proposed_id,
      study_phase_id: phase_id,
      run_key: run_key,
      gust_run_id: gust_run_id
    }
    |> Changeset.change()
    |> Changeset.unique_constraint(:gust_run_id,
      name: :evaluation2_study_phase_runs_gust_run_id_index
    )
    |> Repo.insert()
    |> case do
      {:ok, phase_run} -> {:ok, phase_run}
      {:error, changeset} -> phase_run_result(changeset)
    end
  end

  # The phase lock already decides the phase-and-key race, so a remaining
  # constraint conflict reports one Gust run that another phase already owns.
  defp phase_run_result(changeset) do
    if unique_conflict?(changeset) do
      {:error, error(:conflict, :link_phase_run, :phase_run, changeset)}
    else
      {:error, error(:storage, :link_phase_run, :phase_run, changeset)}
    end
  end

  defp lock_phase(uuid, operation) do
    case Repo.one(from p in Phase, where: p.id == ^uuid, lock: "FOR UPDATE") do
      %Phase{} = phase -> {:ok, phase}
      nil -> {:error, error(:not_found, operation, :phase, nil)}
    end
  end

  # --- evidence snapshots ------------------------------------------------

  # The snapshot belongs to the collection phase that assembled it, so one
  # snapshot exists per phase no matter how often assembly is retried.
  @doc "Prepare one phase-owned evidence snapshot; lifecycle acceptance remains a separate transaction."
  @spec insert_evidence_snapshot(Ecto.UUID.t(), Evidence.t()) ::
          response(EvidenceSnapshot.t())
  def insert_evidence_snapshot(phase_id, evidence) do
    with {:ok, uuid} <- cast_id(phase_id, :insert_evidence_snapshot, :phase),
         {:ok, params} <-
           encode_json(Evidence, :t, evidence, :insert_evidence_snapshot, :evidence) do
      tx(:insert_evidence_snapshot, :evidence_snapshot, fn ->
        snapshot_for_phase(uuid, evidence, params, :insert_evidence_snapshot)
      end)
    end
  end

  defp snapshot_for_phase(phase_id, evidence, params, operation) do
    with {:ok, phase} <- lock_phase(phase_id, operation),
         :ok <- expect_collection_phase(phase, operation) do
      existing_snapshot(phase.id, evidence, params, operation)
    end
  end

  # The phase row lock serializes two assemblies, so the retry reads the stored
  # snapshot instead of provoking a constraint error inside its transaction.
  defp existing_snapshot(phase_id, evidence, params, operation) do
    case Repo.get_by(EvidenceSnapshot, study_phase_id: phase_id) do
      nil -> insert_snapshot(phase_id, params, operation)
      snapshot -> compare_snapshot_evidence(snapshot, evidence, operation)
    end
  end

  defp compare_snapshot_evidence(snapshot, evidence, operation) do
    with {:ok, stored} <- decode_snapshot(snapshot, operation) do
      if stored.evidence == evidence do
        {:ok, stored}
      else
        {:error, error(:conflict, operation, :evidence_snapshot, :different_value)}
      end
    end
  end

  defp insert_snapshot(phase_id, params, operation) do
    %EvidenceSnapshot{study_phase_id: phase_id, evidence: params}
    |> Changeset.change()
    |> Repo.insert()
    |> case do
      {:ok, snapshot} -> decode_snapshot(snapshot, operation)
      {:error, changeset} -> {:error, error(:storage, operation, :evidence_snapshot, changeset)}
    end
  end

  defp expect_collection_phase(%Phase{phase: kind}, operation) do
    if Phase.evidence_role(kind) do
      :ok
    else
      {:error, error(:conflict, operation, :phase, :not_a_collection_phase)}
    end
  end

  # Assembly and lifecycle acceptance both read the snapshot by its owning phase.
  @spec fetch_phase_evidence_snapshot(Ecto.UUID.t()) :: response(EvidenceSnapshot.t())
  def fetch_phase_evidence_snapshot(phase_id) do
    with {:ok, uuid} <- cast_id(phase_id, :fetch_phase_evidence_snapshot, :phase) do
      query = from s in EvidenceSnapshot, where: s.study_phase_id == ^uuid

      fetch_one(:fetch_phase_evidence_snapshot, :evidence_snapshot, query, fn snapshot ->
        decode_snapshot(snapshot, :fetch_phase_evidence_snapshot)
      end)
    end
  end

  # Analysis reads this authoritative context with one joined query and rebuilds
  # no collection history.
  @spec fetch_evidence_context(Ecto.UUID.t()) :: response(evidence_context())
  def fetch_evidence_context(snapshot_id) do
    with {:ok, uuid} <- cast_id(snapshot_id, :fetch_evidence_context, :evidence_snapshot) do
      query =
        from s in EvidenceSnapshot,
          join: p in Phase,
          on: p.id == s.study_phase_id,
          join: e in Execution,
          on: e.id == p.study_execution_id,
          join: r in Revision,
          on: r.id == e.study_revision_id,
          where: s.id == ^uuid,
          select: {s, p, e, r}

      fetch_one(:fetch_evidence_context, :evidence_snapshot, query, fn row ->
        build_evidence_context(row, :fetch_evidence_context)
      end)
    end
  end

  # A snapshot proves preparation only. It can exist before the lifecycle accepts
  # the collection phase.
  @spec snapshot_present?(Ecto.UUID.t()) :: boolean()
  def snapshot_present?(phase_id) do
    not is_nil(Repo.get_by(EvidenceSnapshot, study_phase_id: phase_id))
  end

  # --- shared reads for the two focused owners ---------------------------

  @spec stored_revision(%{study_id: String.t(), revision: pos_integer()}, atom()) ::
          response(Revision.t())
  def stored_revision(identity, operation) do
    case Repo.one(revision_query(identity)) do
      %Revision{} = row -> decode_revision(row, operation)
      nil -> {:error, error(:not_found, operation, :revision, nil)}
    end
  end

  @spec revision_by_id(Ecto.UUID.t(), atom()) :: response(Revision.t())
  def revision_by_id(revision_id, operation) do
    case Repo.get(Revision, revision_id) do
      %Revision{} = row -> decode_revision(row, operation)
      nil -> {:error, error(:storage, operation, :revision, :missing_owner)}
    end
  end

  @spec stored_phase(Ecto.UUID.t(), atom()) :: response(Phase.t())
  def stored_phase(uuid, operation) do
    case Repo.get(Phase, uuid) do
      %Phase{} = phase -> {:ok, phase}
      nil -> {:error, error(:not_found, operation, :phase, nil)}
    end
  end

  @spec stored_phase_run(Ecto.UUID.t(), atom()) :: response(PhaseRun.t())
  def stored_phase_run(uuid, operation) do
    case Repo.get(PhaseRun, uuid) do
      %PhaseRun{} = phase_run -> {:ok, phase_run}
      nil -> {:error, error(:not_found, operation, :phase_run, nil)}
    end
  end

  @spec phase_run_chain(Ecto.UUID.t(), atom()) :: response(phase_run_context())
  def phase_run_chain(uuid, operation) do
    case Repo.one(phase_run_chain_query(uuid)) do
      nil -> {:error, error(:not_found, operation, :phase_run, nil)}
      row -> build_phase_run_context(row, operation)
    end
  end

  @spec stored_result(Ecto.UUID.t(), atom()) :: response(Result.t() | nil)
  def stored_result(execution_id, operation) do
    case Repo.get_by(Result, study_execution_id: execution_id) do
      nil -> {:ok, nil}
      row -> decode_result(row, operation)
    end
  end

  @spec build_lifecycle_context(Execution.t(), Phase.t() | nil, atom()) ::
          response(lifecycle_context())
  def build_lifecycle_context(execution_row, active_phase, operation) do
    with {:ok, execution} <- decode_execution(execution_row, operation),
         {:ok, revision} <- revision_by_id(execution_row.study_revision_id, operation) do
      {:ok, %{execution: execution, revision: revision, active_phase: active_phase}}
    end
  end

  # The successor phase is the durable witness of a committed acceptance.
  @spec phase_present?(Ecto.UUID.t(), Phase.phase_kind()) :: boolean()
  def phase_present?(execution_id, kind) do
    not is_nil(Repo.get_by(Phase, study_execution_id: execution_id, phase: kind))
  end

  # --- shared transaction and containment helpers ------------------------

  @spec error(Error.kind(), atom(), atom(), term()) :: Error.t()
  def error(kind, operation, resource, cause) do
    %Error{kind: kind, operation: operation, resource: resource, cause: cause}
  end

  # Ecto raises `ArgumentError` from its own row loader when a stored JSONB array
  # or scalar cannot load into a `:map` field. Only that loader failure becomes
  # `:corrupt_data`; every other `ArgumentError` stays a programming error.
  @spec contain(atom(), atom(), (-> response(value))) :: response(value) when value: var
  def contain(operation, resource, fun) do
    fun.()
  rescue
    exception in [Postgrex.Error, DBConnection.ConnectionError, DBConnection.OwnershipError] ->
      {:error, error(:storage, operation, resource, exception)}

    exception in ArgumentError ->
      if load_failure?(exception) do
        {:error, error(:corrupt_data, operation, resource, exception)}
      else
        reraise exception, __STACKTRACE__
      end

    exception in RuntimeError ->
      if missing_repo?(exception, __STACKTRACE__) do
        {:error, error(:storage, operation, resource, exception)}
      else
        reraise exception, __STACKTRACE__
      end
  end

  # Run one write transaction and report its committed value.
  @spec tx(atom(), atom(), (-> response(value))) :: response(value) when value: var
  def tx(operation, resource, fun) do
    contain(operation, resource, fn ->
      fun |> run_transaction() |> committed(operation, resource)
    end)
  end

  @spec read(atom(), atom(), (-> value)) :: response(value) when value: var
  def read(operation, resource, query_fun) do
    contain(operation, resource, fn -> {:ok, query_fun.()} end)
  end

  # Run one query and report a missing row as `:not_found`.
  @spec fetch_one(atom(), atom(), Ecto.Queryable.t(), (term() -> response(value))) ::
          response(value)
        when value: var
  def fetch_one(operation, resource, query, build) do
    case read(operation, resource, fn -> Repo.one(query) end) do
      {:ok, nil} -> {:error, error(:not_found, operation, resource, nil)}
      {:ok, row} -> build.(row)
      {:error, failure} -> {:error, failure}
    end
  end

  defp run_transaction(fun) do
    Repo.transaction(fn -> commit_value(fun) end)
  end

  defp commit_value(fun) do
    case fun.() do
      {:ok, value} -> value
      {:error, %Error{} = failure} -> Repo.rollback(failure)
    end
  end

  defp committed({:ok, value}, _operation, _resource), do: {:ok, value}
  defp committed({:error, %Error{} = failure}, _operation, _resource), do: {:error, failure}

  defp committed({:error, cause}, operation, resource) do
    {:error, error(:storage, operation, resource, cause)}
  end

  defp load_failure?(%ArgumentError{message: "cannot load " <> _rest}), do: true
  defp load_failure?(_exception), do: false

  # Ecto raises one plain `RuntimeError` from `Ecto.Repo.Registry.lookup/1` when
  # the named repo process is absent:
  #
  #     could not lookup Ecto repo <name> because it was not started or it does not exist
  #
  # Ecto defines no dedicated exception for that case. The exact message for this
  # repo plus the raising registry frame keep every other `RuntimeError` a
  # programming error.
  defp missing_repo?(%RuntimeError{message: message}, stacktrace) do
    message == missing_repo_message() and Enum.any?(stacktrace, &missing_repo_frame?/1)
  end

  defp missing_repo_message do
    "could not lookup Ecto repo #{inspect(Repo)} because it was not started or it does not exist"
  end

  defp missing_repo_frame?({Ecto.Repo.Registry, :lookup, 1, _location}), do: true
  defp missing_repo_frame?(_stacktrace_entry), do: false

  # --- shared identifier and codec helpers -------------------------------

  # An unusable identifier has the same outcome as a missing row: the caller
  # asked for a record that cannot exist. `Ecto.UUID.cast/1` canonicalizes the
  # accepted form.
  @spec cast_id(term(), atom(), atom()) :: response(Ecto.UUID.t())
  def cast_id(id, operation, resource) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, error(:not_found, operation, resource, :invalid_identifier)}
    end
  end

  @spec cast_identity(term(), atom()) ::
          response(%{study_id: String.t(), revision: pos_integer()})
  def cast_identity(%RevisionIdentity{study_id: study_id, revision: revision}, _operation)
      when is_binary(study_id) and is_integer(revision) and revision > 0 do
    {:ok, %{study_id: study_id, revision: revision}}
  end

  def cast_identity(_revision_ref, operation) do
    {:error, error(:not_found, operation, :revision, :invalid_identity)}
  end

  @spec unique_conflict?(Changeset.t()) :: boolean()
  def unique_conflict?(%Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  @spec encode_json(module(), atom(), term(), atom(), atom()) :: response(map())
  def encode_json(module, type, value, operation, resource) do
    case Spectral.encode(value, module, type, :json, [:pre_encoded]) do
      {:ok, params} when is_map(params) ->
        {:ok, params}

      {:ok, other} ->
        {:error, error(:storage, operation, resource, {:not_a_json_object, other})}

      {:error, errors} ->
        {:error, error(:storage, operation, resource, errors)}
    end
  end

  @spec decode_json(module(), atom(), term(), atom(), atom()) :: response(term())
  def decode_json(module, type, value, operation, resource) do
    case Spectral.decode(value, module, type, :json, [:pre_decoded]) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, errors} -> {:error, error(:corrupt_data, operation, resource, errors)}
    end
  end

  @spec decode_optional_json(module(), atom(), term(), atom(), atom()) :: response(term())
  def decode_optional_json(_module, _type, nil, _operation, _resource), do: {:ok, nil}

  def decode_optional_json(module, type, value, operation, resource),
    do: decode_json(module, type, value, operation, resource)

  # --- private record decoding -------------------------------------------

  defp build_phase_context({phase, execution, revision}, operation) do
    with {:ok, {execution, revision}} <- decode_chain({execution, revision}, operation) do
      {:ok, %{phase: phase, execution: execution, revision: revision}}
    end
  end

  defp build_phase_run_context({phase_run, phase, execution, revision}, operation) do
    with {:ok, {execution, revision}} <- decode_chain({execution, revision}, operation) do
      {:ok, %{phase_run: phase_run, phase: phase, execution: execution, revision: revision}}
    end
  end

  defp build_evidence_context({snapshot, phase, execution, revision}, operation) do
    with {:ok, snapshot} <- decode_snapshot(snapshot, operation),
         {:ok, {execution, revision}} <- decode_chain({execution, revision}, operation) do
      {:ok, %{snapshot: snapshot, phase: phase, execution: execution, revision: revision}}
    end
  end

  defp phase_run_chain_query(uuid) do
    from pr in PhaseRun,
      join: p in Phase,
      on: p.id == pr.study_phase_id,
      join: e in Execution,
      on: e.id == p.study_execution_id,
      join: r in Revision,
      on: r.id == e.study_revision_id,
      where: pr.id == ^uuid,
      select: {pr, p, e, r}
  end

  defp decode_chain({execution, revision}, operation) do
    with {:ok, execution} <- decode_execution(execution, operation),
         {:ok, revision} <- decode_revision(revision, operation) do
      {:ok, {execution, revision}}
    end
  end

  defp decode_execution(%Execution{} = execution, operation) do
    with {:ok, pilot_outcome} <-
           decode_optional_json(
             PilotOutcome,
             :t,
             execution.pilot_outcome,
             operation,
             :pilot_outcome
           ),
         {:ok, selection} <-
           decode_optional_json(Selection, :t, execution.selection, operation, :selection),
         {:ok, public_error} <-
           decode_optional_json(
             StudyError,
             :t,
             execution.error,
             operation,
             :execution_error
           ) do
      {:ok,
       %{execution | pilot_outcome: pilot_outcome, selection: selection, error: public_error}}
    end
  end

  defp decode_revision(%Revision{} = revision, operation) do
    case decode_json(Definition, :t, revision.definition, operation, :definition) do
      {:ok, definition} -> {:ok, %{revision | definition: definition}}
      {:error, failure} -> {:error, failure}
    end
  end

  defp decode_snapshot(%EvidenceSnapshot{} = snapshot, operation) do
    case decode_json(Evidence, :t, snapshot.evidence, operation, :evidence) do
      {:ok, evidence} -> {:ok, %{snapshot | evidence: evidence}}
      {:error, failure} -> {:error, failure}
    end
  end

  defp decode_result(%Result{} = result, operation) do
    with {:ok, family} <-
           decode_json(CorrectedFamily, :t, result.family, operation, :final_family),
         {:ok, timing} <- decode_json(Timing, :t, result.timing, operation, :final_timing) do
      {:ok, %{result | family: family, timing: timing}}
    end
  end
end
