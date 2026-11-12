defmodule NetworkDefenseWeb.StudyRequests do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2, push_event: 3]

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefenseWeb.Contracts.Dashboard.Study.Request
  alias NetworkDefenseWeb.{StudyObserver, StudyWire}

  @events ~w(fetch_study_options create_study_revision fetch_study_revisions fetch_study_revision fetch_study_executions start_study_execution continue_study_execution approve_study_final cancel_study_execution fetch_study_status fetch_study_pilot_result fetch_study_result watch_study_execution unwatch_study_execution close_study_document)
  def events, do: @events

  def init(socket), do: socket |> assign(:study_watches, %{}) |> assign(:study_pending, %{})

  def handle_event(event, params, socket) do
    case validate(event, params) do
      {:ok, request} ->
        dispatch(event, request, socket)

      {:error, reply} ->
        {:reply, reply, socket}
    end
  end

  defp validate(event, params) do
    with true <- is_map(params) and :erlang.external_size(params) <= 262_144,
         {:ok, request} <- Request.validate(params),
         true <- valid_common?(request),
         true <- valid_required?(event, request) do
      {:ok, request}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, StudyWire.validation_error(changeset)}

      _ ->
        {:error, StudyWire.error("invalid_request", "Check the study request fields and size.")}
    end
  end

  defp valid_common?(r) do
    Enum.all?([
      Enum.all?(
        [r.document_id, r.watch_id, r.request_id, r.candidate_id],
        &optional_text?(&1, 160)
      ),
      optional_uuid?(r.execution_id),
      optional_text?(r.query, 200),
      optional_range?(r.limit, 1..100),
      optional_range?(r.offset, 0..100_000),
      optional_range?(r.timeout_ms, 0..60_000)
    ])
  end

  defp optional_text?(nil, _max), do: true
  defp optional_text?(value, max), do: is_binary(value) and byte_size(value) <= max
  defp optional_uuid?(nil), do: true
  defp optional_uuid?(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp optional_range?(nil, _range), do: true
  defp optional_range?(value, range), do: value in range

  @required_fields %{
    "create_study_revision" => [:definition],
    "close_study_document" => [:document_id],
    "watch_study_execution" => [:execution_id, :document_id, :watch_id],
    "unwatch_study_execution" => [:document_id, :watch_id],
    "continue_study_execution" => [:execution_id, :document_id, :request_id]
  }
  defp valid_required?(event, r)
       when event in ["fetch_study_revision", "fetch_study_executions", "start_study_execution"],
       do: valid_revision?(r.revision)

  defp valid_required?(event, _r) when event in ["fetch_study_options", "fetch_study_revisions"],
    do: true

  defp valid_required?("approve_study_final", r),
    do: not is_nil(r.execution_id) and valid_approval?(r)

  defp valid_required?(event, r),
    do:
      Enum.all?(
        Map.get(@required_fields, event, [:execution_id]),
        &(Map.get(r, &1) not in [nil, ""])
      )

  defp valid_approval?(%{approval: "recommended"}), do: true

  defp valid_approval?(%{approval: "override_insufficient", candidate_id: id}),
    do: is_binary(id) and id != ""

  defp valid_approval?(_r), do: false

  defp valid_revision?(%{study_id: id, revision: revision}),
    do: is_binary(id) and byte_size(id) in 1..160 and is_integer(revision) and revision > 0

  defp valid_revision?(_), do: false
  defp revision(r), do: %Revision{study_id: r.revision.study_id, revision: r.revision.revision}

  defp page(r) do
    limit = r.limit || 25
    %{page_size: limit, page: div(r.offset || 0, limit) + 1, search: r.query || ""}
  end

  defp dispatch("continue_study_execution", r, socket), do: continue(r, socket)
  defp dispatch("watch_study_execution", r, socket), do: watch(r, socket)

  defp dispatch("cancel_study_execution", r, socket) do
    case Study.cancel(r.execution_id) do
      {:ok, status} ->
        socket = finish_cancelled_caller(socket, r.execution_id, status)
        {:reply, StudyWire.validate_reply(response({:ok, status}, :execution)), socket}

      {:error, error} ->
        {:reply, StudyWire.reply({:error, error}), socket}
    end
  end

  defp dispatch("unwatch_study_execution", r, socket) do
    {:reply, %{status: "ok"},
     release_watches(socket, fn {document, watch}, _ ->
       document == r.document_id and watch == r.watch_id
     end)}
  end

  defp dispatch("close_study_document", r, socket) do
    socket = release_watches(socket, fn {document, _watch}, _ -> document == r.document_id end)

    socket =
      Enum.reduce(socket.assigns.study_pending, socket, fn {id, pending}, acc ->
        if pending.document_id == r.document_id do
          acc
          |> assign(:study_pending, Map.delete(acc.assigns.study_pending, id))
          |> cancel_async({:study_continue, id, pending.request_id})
        else
          acc
        end
      end)

    {:reply, %{status: "ok"}, socket}
  end

  defp dispatch(event, r, socket) do
    reply = read_or_command(event, r)
    {:reply, StudyWire.validate_reply(reply), socket}
  end

  defp finish_cancelled_caller(socket, id, status) do
    case socket.assigns.study_pending[id] do
      %{request_id: request_id} ->
        socket
        |> cancel_async({:study_continue, id, request_id})
        |> finished(id, request_id, {:ok, {:ok, status}})

      nil ->
        socket
    end
  end

  defp read_or_command("fetch_study_options", r) do
    reply = response(Study.definition_options(), :options)

    if r.document_id do
      update_in(
        reply.options,
        &Map.merge(&1, %{study_id: r.document_id, family_id: "family-" <> r.document_id})
      )
    else
      reply
    end
  end

  defp read_or_command("create_study_revision", r),
    do:
      response(
        Study.create_revision_from_params(StudyWire.definition_params(r.definition)),
        :revision
      )

  defp read_or_command("fetch_study_revision", r),
    do: response(Study.get_revision(revision(r)), :detail)

  defp read_or_command("fetch_study_revisions", r),
    do: list_response(Study.list_revisions(page(r)), :revisions)

  defp read_or_command("fetch_study_executions", r),
    do: list_response(Study.list_executions(revision(r), page(r)), :executions)

  defp read_or_command("start_study_execution", r),
    do: response(Study.start(revision(r)), :execution)

  defp read_or_command("fetch_study_status", r) do
    case Study.progress(r.execution_id) do
      {:ok, progress} ->
        %{
          status: "ok",
          execution: StudyWire.wire(progress.status),
          progress: StudyWire.wire(progress)
        }

      {:error, error} ->
        StudyWire.reply({:error, error})
    end
  end

  defp read_or_command("fetch_study_pilot_result", r),
    do: response(Study.pilot_result(r.execution_id), :pilot, &StudyWire.pilot/1)

  defp read_or_command("fetch_study_result", r),
    do: response(Study.result(r.execution_id), :result, &StudyWire.result/1)

  defp read_or_command("approve_study_final", r) do
    approval =
      if r.approval == "recommended",
        do: :recommended,
        else: {:override_insufficient, r.candidate_id}

    response(Study.resume(r.execution_id, approval), :execution)
  end

  defp response(result, key, mapper \\ &StudyWire.wire/1)
  defp response({:ok, value}, key, mapper), do: %{key => mapper.(value), :status => "ok"}
  defp response({:error, error}, _key, _mapper), do: StudyWire.reply({:error, error})

  defp list_response({:ok, page}, key),
    do: %{key => StudyWire.wire(page.entries), :status => "ok", :total => page.total}

  defp list_response({:error, error}, _key), do: StudyWire.reply({:error, error})

  defp continue(r, socket) do
    with false <- Map.has_key?(socket.assigns.study_pending, r.execution_id),
         true <- map_size(socket.assigns.study_pending) < 20,
         {:ok, status} <- Study.status(r.execution_id),
         true <- Lifecycle.active?(status.state) do
      pending = %{document_id: r.document_id, request_id: r.request_id}

      socket =
        socket
        |> assign(:study_pending, Map.put(socket.assigns.study_pending, r.execution_id, pending))
        |> start_async({:study_continue, r.execution_id, r.request_id}, fn ->
          Study.continue(r.execution_id, timeout: r.timeout_ms || 30_000)
        end)

      {:reply, %{status: "accepted", request_id: r.request_id, execution: StudyWire.wire(status)},
       socket}
    else
      _ ->
        {:reply,
         StudyWire.error(
           "continue_rejected",
           "This execution cannot start another continuation request."
         ), socket}
    end
  end

  defp watch(r, socket) do
    key = {r.document_id, r.watch_id}

    with true <- map_size(socket.assigns.study_watches) < 40,
         false <- Map.has_key?(socket.assigns.study_watches, key),
         {:ok, _status} <- Study.status(r.execution_id),
         {:ok, observer} <-
           StudyObserver.start_link(
             owner: self(),
             document_id: r.document_id,
             execution_id: r.execution_id,
             watch_id: r.watch_id
           ) do
      socket =
        assign(socket, :study_watches, Map.put(socket.assigns.study_watches, key, observer))

      {:reply, %{status: "ok", watch_id: r.watch_id}, socket}
    else
      _ ->
        {:reply, StudyWire.error("watch_rejected", "The study execution cannot be observed."),
         socket}
    end
  end

  defp release_watches(socket, predicate) do
    {released, retained} =
      Enum.split_with(socket.assigns.study_watches, fn {key, pid} -> predicate.(key, pid) end)

    Enum.each(released, fn {_key, pid} ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end)

    assign(socket, :study_watches, Map.new(retained))
  end

  def close_session(socket) do
    Enum.each(socket.assigns.study_pending, fn {id, pending} ->
      cancel_async(socket, {:study_continue, id, pending.request_id})
    end)

    release_watches(socket, fn _key, _pid -> true end)
    :ok
  end

  def observed(socket, event) do
    if Map.has_key?(socket.assigns.study_watches, {event.document_id, event.watch_id}) do
      push_event(socket, "study_progress", event)
    else
      socket
    end
  end

  def finished(socket, id, request_id, result) do
    case socket.assigns.study_pending[id] do
      %{request_id: ^request_id, document_id: document_id} ->
        values =
          case result do
            {:ok, {:ok, status}} ->
              %{status: StudyWire.wire(status)}

            {:ok, {:error, error}} ->
              %{error: StudyWire.wire(error)}

            {:exit, _reason} ->
              Map.take(
                StudyWire.error(
                  "continue_interrupted",
                  "The continuation request ended. Refresh status before continuing."
                ),
                [:error]
              )
          end

        event =
          Map.merge(values, %{document_id: document_id, execution_id: id, request_id: request_id})

        socket
        |> assign(:study_pending, Map.delete(socket.assigns.study_pending, id))
        |> push_event("study_continue_finished", event)

      _ ->
        socket
    end
  end
end
