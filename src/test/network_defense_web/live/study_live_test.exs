defmodule NetworkDefenseWeb.StudyLiveTest do
  use NetworkDefenseWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation2.Study

  alias NetworkDefense.Evaluation2.Study.{
    AuthoredDefinition,
    Definition,
    Evidence,
    Persistence,
    PilotOutcome,
    Workflow
  }

  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2Test.UiFixtures
  alias NetworkDefenseWeb.StudyWire

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    attrs = UiFixtures.attrs()
    {:ok, revision} = Study.create_revision_from_params(attrs)
    {:ok, context} = Persistence.Executions.start_execution(revision)
    %{revision: revision, execution_id: context.execution.id, attrs: attrs}
  end

  test "structured freeze, exact seed, bounded requests and missing reads cross generated contracts",
       c do
    {:ok, view, _} = live(c.conn, ~p"/")
    {:ok, parsed} = Definition.parse(c.attrs)
    document_id = Ecto.UUID.generate()

    for _ <- 1..2 do
      render_hook(view, "fetch_study_options", %{document_id: document_id})

      assert_reply(view, %{status: "ok", options: %{study_id: ^document_id, family_id: family_id}})

      assert family_id == "family-" <> document_id
    end

    authored = parsed |> AuthoredDefinition.new() |> StudyWire.wire()

    authored =
      Map.merge(authored, %{
        study_id: document_id,
        family_id: "family-" <> document_id,
        name: "  Defense study  "
      })

    for _ <- 1..2 do
      render_hook(view, "create_study_revision", %{definition: authored})
      assert_reply(view, %{status: "ok", revision: %{study_id: ^document_id, revision: 1}})
    end

    render_hook(view, "fetch_study_revision", %{revision: %{study_id: document_id, revision: 1}})

    assert_reply(view, %{
      status: "ok",
      detail: %{authored: %{name: "Defense study", seed: "9007199254740993"}}
    })

    render_hook(view, "fetch_study_revisions", %{query: "Defense study"})
    assert_reply(view, %{status: "ok", revisions: [%{name: "Defense study"}]})
    render_hook(view, "fetch_study_revisions", %{limit: 101})
    assert_reply(view, %{status: "error", error: %{issues: [%{code: "invalid_request"}]}})
    render_hook(view, "fetch_study_revision", %{revision: %{study_id: "missing", revision: 1}})
    assert_reply(view, %{status: "error", error: %{issues: [%{code: "revision_not_found"}]}})
    render_hook(view, "fetch_study_revisions", %{query: String.duplicate("x", 300_000)})
    assert_reply(view, %{status: "error"})
  end

  test "raw form strings are cast and validated at the backend boundary", c do
    {:ok, view, _} = live(c.conn, ~p"/")
    {:ok, parsed} = Definition.parse(c.attrs)
    authored = parsed |> AuthoredDefinition.new() |> StudyWire.wire() |> form_values()

    render_hook(view, "create_study_revision", %{definition: authored})
    assert_reply(view, %{status: "ok", revision: %{study_id: "ui-test", revision: 1}})

    render_hook(view, "fetch_study_revision", %{revision: StudyWire.wire(c.revision)})
    assert_reply(view, %{status: "ok", detail: %{authored: %{seed: "9007199254740993"}}})

    invalid = authored |> Map.put(:revision, "") |> Map.put(:family_alpha, "not a number")
    invalid = put_in(invalid, [:tiers, Access.at(0), :budgets], ["1", "bad"])
    render_hook(view, "create_study_revision", %{definition: invalid})

    assert_reply(view, %{status: "error", error: %{category: "validation_failed", issues: issues}})

    paths = Enum.map(issues, & &1.path)
    assert ["definition", "revision"] in paths
    assert ["definition", "family_alpha"] in paths
    assert ["definition", "tiers", 0, "budgets", 1] in paths
    refute ["definition", "tiers", 0, "budgets", 0] in paths

    render_hook(view, "create_study_revision", %{definition: Map.put(authored, :revision, "-1")})
    assert_reply(view, %{status: "error", error: %{category: "validation_failed"}})
  end

  defp form_values(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, form_values(item)} end)

  defp form_values(value) when is_list(value), do: Enum.map(value, &form_values/1)
  defp form_values(value) when is_number(value), do: to_string(value)
  defp form_values(value), do: value

  test "controlled recommended approval freezes its exact declared counts and rejects an override",
       c do
    controlled_gate(c.execution_id, %PilotOutcome{
      outcome: :recommended,
      candidate_id: "tiny",
      plan_count_per_side: 1,
      attacks_per_plan: 2
    })

    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "approve_study_final", %{
      execution_id: c.execution_id,
      approval: "override_insufficient",
      candidate_id: "tiny"
    })

    assert_reply(view, %{status: "error", error: %{issues: [%{code: "invalid_approval"}]}})
    assert {:ok, %{state: :awaiting_final}} = Study.status(c.execution_id)

    render_hook(view, "approve_study_final", %{
      execution_id: c.execution_id,
      approval: "recommended"
    })

    assert_reply(view, %{
      status: "ok",
      execution: %{
        execution_id: id,
        state: "collecting_final",
        selection: %{candidate_id: "tiny", plan_count_per_side: 1, attacks_per_plan: 2}
      }
    })

    assert id == c.execution_id
  end

  test "controlled insufficient approval rejects an undeclared candidate", c do
    controlled_gate(c.execution_id, %PilotOutcome{outcome: :insufficient})
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "approve_study_final", %{
      execution_id: c.execution_id,
      approval: "override_insufficient",
      candidate_id: "undeclared"
    })

    assert_reply(view, %{status: "error", error: %{issues: [%{code: "invalid_approval"}]}})
    assert {:ok, %{state: :awaiting_final}} = Study.status(c.execution_id)

    render_hook(view, "approve_study_final", %{
      execution_id: c.execution_id,
      approval: "override_insufficient",
      candidate_id: "tiny"
    })

    assert_reply(view, %{
      status: "ok",
      execution: %{
        state: "collecting_final",
        selection: %{candidate_id: "tiny", plan_count_per_side: 1, attacks_per_plan: 2}
      }
    })
  end

  test "Continue acknowledges before completion and correlates a finite-timeout return", c do
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "continue_study_execution", %{
      document_id: "doc",
      execution_id: c.execution_id,
      request_id: "request",
      timeout_ms: 0
    })

    assert_reply(view, %{
      status: "accepted",
      request_id: "request",
      execution: %{execution_id: id}
    })

    assert id == c.execution_id

    assert_push_event(view, "study_continue_finished", %{
      document_id: "doc",
      execution_id: ^id,
      request_id: "request",
      status: %{state: "collecting_pilot"}
    })

    render_hook(view, "fetch_study_status", %{execution_id: id})
    assert_reply(view, %{execution: %{state: "collecting_pilot"}})
  end

  test "one continuation per execution survives unrelated reads and document close ends only the caller",
       c do
    block_continuation()
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "continue_study_execution", %{
      document_id: "doc",
      execution_id: c.execution_id,
      request_id: "request"
    })

    assert_reply(view, %{status: "accepted"})
    assert_receive {:continuation, caller}, 1_000
    monitor = Process.monitor(caller)
    render_hook(view, "fetch_study_options", %{})
    assert_reply(view, %{status: "ok"})
    assert Process.alive?(caller)

    render_hook(view, "continue_study_execution", %{
      document_id: "another",
      execution_id: c.execution_id,
      request_id: "duplicate"
    })

    assert_reply(view, %{status: "error", error: %{issues: [%{code: "continue_rejected"}]}})
    render_hook(view, "close_study_document", %{document_id: "doc"})
    assert_reply(view, %{status: "ok"})
    assert_receive {:DOWN, ^monitor, :process, ^caller, _}, 1_000
    assert {:ok, %{state: :collecting_pilot}} = Study.status(c.execution_id)
    refute_push_event(view, "study_continue_finished", %{})
  end

  test "cancellation reconciles and ends a pending continuation caller", c do
    block_continuation()
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "continue_study_execution", %{
      document_id: "doc",
      execution_id: c.execution_id,
      request_id: "request"
    })

    assert_reply(view, %{status: "accepted"})
    assert_receive {:continuation, caller}, 1_000
    monitor = Process.monitor(caller)
    render_hook(view, "cancel_study_execution", %{execution_id: c.execution_id})
    assert_reply(view, %{execution: %{state: "cancelled"}})

    assert_push_event(view, "study_continue_finished", %{
      request_id: "request",
      status: %{state: "cancelled"}
    })

    assert_receive {:DOWN, ^monitor, :process, ^caller, _}, 1_000
  end

  test "disconnect ends the continuation caller and reopening needs an explicit request", c do
    block_continuation()
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "continue_study_execution", %{
      document_id: "doc",
      execution_id: c.execution_id,
      request_id: "request"
    })

    assert_reply(view, %{status: "accepted"})
    assert_receive {:continuation, caller}, 1_000
    monitor = Process.monitor(caller)
    GenServer.stop(view.pid, :normal)
    assert_receive {:DOWN, ^monitor, :process, ^caller, _}, 1_000
    {:ok, reopened, _} = live(c.conn, ~p"/")
    render_hook(reopened, "fetch_study_status", %{execution_id: c.execution_id})
    assert_reply(reopened, %{execution: %{state: "collecting_pilot"}})
    refute_receive {:continuation, _}, 50
  end

  test "watch identities route accepted state and close releases observation", c do
    {:ok, view, _} = live(c.conn, ~p"/")

    render_hook(view, "watch_study_execution", %{
      document_id: "doc",
      execution_id: c.execution_id,
      watch_id: "watch"
    })

    assert_reply(view, %{status: "ok", watch_id: "watch"})

    assert_push_event(view, "study_progress", %{
      document_id: "doc",
      watch_id: "watch",
      sequence: 1,
      status: %{state: "collecting_pilot"}
    })

    render_hook(view, "cancel_study_execution", %{execution_id: c.execution_id})
    assert_reply(view, %{execution: %{state: "cancelled"}})

    assert_push_event(view, "study_progress", %{
      watch_id: "watch",
      status: %{state: "cancelled"}
    })

    render_hook(view, "close_study_document", %{document_id: "doc"})
    assert_reply(view, %{status: "ok"})

    send(
      view.pid,
      {:study_observed,
       %{document_id: "doc", execution_id: c.execution_id, watch_id: "watch", sequence: 999}}
    )

    refute_push_event(view, "study_progress", %{sequence: 999})
  end

  test "structured error paths preserve integer indexes" do
    reply =
      StudyWire.validate_reply(%{
        status: "error",
        error: %{
          category: "validation_failed",
          issues: [%{code: "invalid", path: ["tiers", 1, "budgets", 0], message: "Check budget."}]
        }
      })

    assert reply.error.issues |> hd() |> Map.fetch!(:path) == ["tiers", 1, "budgets", 0]
  end

  # Controlled acceptance fixtures exercise web approval. Real Pilot execution has separate browser evidence.
  defp controlled_gate(id, outcome) do
    {:ok, context} = Executions.fetch_context(id)

    {:ok, _snapshot} =
      Persistence.insert_evidence_snapshot(context.active_phase.id, %Evidence{comparisons: []})

    {:ok, analysis} = Executions.accept_pilot_collection(context.active_phase.id)
    {:ok, _gate} = Executions.accept_pilot_analysis(analysis.active_phase.id, outcome)
  end

  defp block_continuation do
    parent = self()
    :meck.new(Workflow, [:passthrough, :no_link])

    :meck.expect(Workflow, :continue, fn id, _opts ->
      send(parent, {:continuation, self()})

      receive do
        :finish -> Study.status(id)
      end
    end)

    on_exit(fn -> :meck.unload(Workflow) end)
  end
end
