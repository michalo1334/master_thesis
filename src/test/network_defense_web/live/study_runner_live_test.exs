defmodule NetworkDefenseWeb.StudyRunnerLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudySession
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefenseWeb.DashboardLive

  @phases ~w(building_bundle submitting_analysis waiting_for_service validating_result complete)
  @timeout 5_000

  defmacro study_event(view, event, payload) do
    quote do
      assert_push_event(unquote(view), unquote(event), unquote(payload), @timeout)
    end
  end

  setup do
    manifest_id = "study-live-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.analysis_manifest())

    run = EvaluationFixtures.completed_run(manifest_id)

    final_manifest_id = "study-live-final-#{System.unique_integer([:positive])}"

    assert {:ok, _final_manifest} =
             EvaluationFixtures.save_manifest(
               final_manifest_id,
               EvaluationFixtures.final_manifest()
             )

    final_run = EvaluationFixtures.completed_run(final_manifest_id)

    assert {:ok, specification} =
             EvaluationFixtures.save_study_specification(single_tier_specification())

    %{
      run: run,
      final_run: final_run,
      manifest_id: manifest_id,
      specification: specification
    }
  end

  defp final_selection(final_run), do: [%{"tier" => "small", "run_id" => final_run.id}]

  describe "list_study_tier_runs" do
    test "lists runs for a declared tier and rejects an invalid payload", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "list_study_tier_runs", %{
        "specification_id" => specification.id,
        "tier" => "small",
        "mode" => "pilot"
      })

      assert_reply(view, %{runs: runs, required_inputs: required_inputs})

      assert required_inputs =~ "strategies: simulation_informed"

      assert Enum.any?(runs, fn summary ->
               summary.id == run.id and summary.manifest_title == "T" and summary.plan_count == 2 and
                 summary.trial_count == 6
             end)

      render_hook(view, "list_study_tier_runs", %{
        "specification_id" => specification.id,
        "tier" => "large",
        "mode" => "pilot"
      })

      assert_reply(view, %{runs: []})

      render_hook(view, "list_study_tier_runs", %{"unexpected" => true})

      assert_reply(view, %{runs: []})
    end
  end

  describe "preflight_study" do
    test "preflights a locked mapping and reports stable errors", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "preflight_study", %{
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{
        status: "ok",
        study_id: "topology-scale-study",
        specification_version: 1,
        tier_count: 1,
        errors: []
      })

      render_hook(view, "preflight_study", %{
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => []
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "no_tiers"}]})

      render_hook(view, "preflight_study", %{
        "specification_id" => Ecto.UUID.generate(),
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "specification_not_found"}]})

      render_hook(view, "preflight_study", %{})

      assert_reply(view, %{status: "invalid_request", errors: []})
    end

    test "rejects a completed warm-up run and an incompatible run with dedicated codes", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      warmup = warmup_run()
      incompatible = incompatible_run()

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "preflight_study", %{
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => warmup.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "run_warmup"}]})

      render_hook(view, "preflight_study", %{
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => incompatible.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "run_incompatible"}]})

      render_hook(view, "preflight_study", %{
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "ok", required_inputs: required_inputs})
      assert required_inputs =~ "baseline: cvss"
    end
  end

  describe "start_study_analysis pilot" do
    test "emits named phases and returns the exact result zip", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      test_pid = self()

      expect_analysis(fn bundle, _study_id, :pilot ->
        archive = EvaluationFixtures.study_result_archive_for_bundle("pilot", bundle)
        send(test_pid, {:result_archive, archive})
        {:ok, archive}
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{
        status: "accepted",
        document_id: ^document_id,
        mode: "pilot",
        attempt_id: attempt_id,
        errors: []
      })

      assert is_binary(attempt_id)
      assert attempt_id != ""

      Enum.each(@phases, fn phase ->
        study_event(view, "study_analysis_progress", %{
          document_id: ^document_id,
          mode: "pilot",
          attempt_id: ^attempt_id,
          phase: ^phase
        })
      end)

      study_event(view, "study_analysis_ready", %{
        document_id: ^document_id,
        mode: "pilot",
        attempt_id: ^attempt_id,
        archive: encoded,
        pilot_eligible: true,
        analysis: %{metadata: %{command_mode: "study-pilot"}}
      })

      assert_receive {:result_archive, archive}
      assert Base.decode64!(encoded) == archive
    end

    test "rejects an invalid payload and an unknown tier run", %{
      conn: conn,
      specification: specification
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "start_study_analysis", %{})
      assert_reply(view, %{status: "invalid_request", document_id: nil, mode: nil})

      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => Ecto.UUID.generate()}]
      })

      assert_reply(view, %{status: "rejected", mode: "pilot", errors: [%{code: "run_not_found"}]})
    end

    test "rejects a warm-up run with the dedicated wire code", %{
      conn: conn,
      specification: specification
    } do
      warmup = warmup_run()

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => warmup.id}]
      })

      assert_reply(view, %{status: "rejected", mode: "pilot", errors: [%{code: "run_warmup"}]})
    end

    test "rejects start when persisted plan seeds are outside the Pilot schedule", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      plan =
        OptimizationRun
        |> where([plan], plan.evaluation_run_id == ^run.id)
        |> limit(1)
        |> Repo.one!()

      {:ok, _plan} = plan |> Ecto.Changeset.change(selection_seed: 999_999) |> Repo.update()

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "start_study_analysis", %{
        "document_id" => Ecto.UUID.generate(),
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "run_incompatible"}]})
    end

    test "rejects a pilot without a specification or tiers", %{conn: conn, run: run} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "start_study_analysis", %{
        "document_id" => Ecto.UUID.generate(),
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "invalid_request"}]})
    end

    test "rejects a different mapping for a locked document", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      expect_analysis(fn _bundle, _study_id, :pilot ->
        {:ok, EvaluationFixtures.pilot_eligible_archive()}
      end)

      assert {:ok, other} =
               EvaluationFixtures.save_study_specification(
                 single_tier_specification()
                 |> Map.put("study_id", "other-study")
               )

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot"})

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => other.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "document_locked"}]})
    end

    test "keeps locked inputs for an in-place retry after a service error", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      expect_analysis(fn _bundle, _study_id, :pilot -> {:error, :transport} end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      }

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted"})

      study_event(view, "study_analysis_error", %{
        document_id: ^document_id,
        mode: "pilot",
        phase: "waiting_for_service",
        error: %{code: "transport"}
      })

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted", document_id: ^document_id})
      study_event(view, "study_analysis_error", %{mode: "pilot", error: %{code: "transport"}})
    end

    test "correlates each retry with a fresh attempt identity", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      expect_analysis(fn _bundle, _study_id, :pilot -> {:error, :transport} end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      }

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted", attempt_id: first_attempt})

      study_event(view, "study_analysis_error", %{
        document_id: ^document_id,
        mode: "pilot",
        attempt_id: ^first_attempt,
        error: %{code: "transport"}
      })

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted", attempt_id: second_attempt})

      assert first_attempt != second_attempt

      study_event(view, "study_analysis_error", %{
        document_id: ^document_id,
        mode: "pilot",
        attempt_id: ^second_attempt,
        error: %{code: "transport"}
      })
    end

    test "owns one task per document", %{conn: conn, run: run, specification: specification} do
      archive = EvaluationFixtures.pilot_eligible_archive()
      test_pid = self()

      expect_analysis(fn _bundle, _study_id, :pilot ->
        send(test_pid, {:analysis_started, self()})

        receive do
          :release -> {:ok, archive}
        after
          5_000 -> {:ok, archive}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      }

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted"})
      assert_receive {:analysis_started, analysis_pid}, @timeout

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "rejected", errors: [%{code: "already_running"}]})

      render_hook(view, "close_study_document", %{"document_id" => document_id})
      assert_reply(view, %{status: "closed"})

      wait_until(fn -> not Process.alive?(analysis_pid) end)
      refute Process.alive?(analysis_pid)
    end
  end

  describe "final gate" do
    test "enables final only after an eligible pilot for the locked inputs", %{
      conn: conn,
      run: run,
      final_run: final_run,
      specification: specification
    } do
      pilot_archive = EvaluationFixtures.pilot_eligible_archive()
      final_archive = EvaluationFixtures.final_archive()

      expect_analysis(fn _bundle, _study_id, mode ->
        case mode do
          :pilot -> {:ok, pilot_archive}
          :analyze -> {:ok, final_archive}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: true})

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => final_selection(final_run)
      })

      assert_reply(view, %{status: "accepted", document_id: ^document_id, mode: "final"})

      study_event(view, "study_analysis_ready", %{
        document_id: ^document_id,
        mode: "final",
        archive: encoded,
        pilot_eligible: nil,
        analysis: %{metadata: %{command_mode: "study-analyze"}}
      })

      assert is_binary(Base.decode64!(encoded))
    end

    test "keeps final disabled for an insufficient pilot and allows an identical rerun", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      insufficient = EvaluationFixtures.pilot_insufficient_archive()

      expect_analysis(fn _bundle, _study_id, :pilot -> {:ok, insufficient} end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      }

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted"})

      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: false})

      render_hook(view, "start_study_analysis", %{"document_id" => document_id, "mode" => "final"})

      assert_reply(view, %{status: "rejected", errors: [%{code: "final_not_available"}]})

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted", document_id: ^document_id, mode: "pilot"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: false})
    end

    test "keeps final disabled for a non-informative pilot", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      non_informative = EvaluationFixtures.pilot_non_informative_archive()

      expect_analysis(fn _bundle, _study_id, :pilot -> {:ok, non_informative} end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: false})

      render_hook(view, "start_study_analysis", %{"document_id" => document_id, "mode" => "final"})

      assert_reply(view, %{status: "rejected", errors: [%{code: "final_not_available"}]})
    end

    test "a failed pilot rerun denies final", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      pilot_archive = EvaluationFixtures.pilot_eligible_archive()
      test_pid = self()

      expect_analysis(fn _bundle, _study_id, :pilot ->
        send(test_pid, {:pilot_attempt, self()})

        receive do
          {:reply, reply} -> reply
        after
          5_000 -> {:ok, pilot_archive}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      }

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted"})
      assert_receive {:pilot_attempt, first_pid}, @timeout
      send(first_pid, {:reply, {:ok, pilot_archive}})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: true})

      render_hook(view, "start_study_analysis", payload)
      assert_reply(view, %{status: "accepted"})
      assert_receive {:pilot_attempt, second_pid}, @timeout
      send(second_pid, {:reply, {:error, :transport}})

      study_event(view, "study_analysis_error", %{
        document_id: ^document_id,
        mode: "pilot",
        error: %{code: "transport"}
      })

      render_hook(view, "start_study_analysis", %{"document_id" => document_id, "mode" => "final"})

      assert_reply(view, %{status: "rejected", errors: [%{code: "final_not_available"}]})
    end

    test "rejects final without server-held pilot state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "start_study_analysis", %{
        "document_id" => Ecto.UUID.generate(),
        "mode" => "final"
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "document_not_found"}]})
    end

    test "rejects a final mapping that reuses a pilot run", %{
      conn: conn,
      run: run,
      specification: specification
    } do
      expect_analysis(fn _bundle, _study_id, :pilot ->
        {:ok, EvaluationFixtures.pilot_eligible_archive()}
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: true})

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "run_overlap"}]})
    end

    test "rejects an invalid final mapping without locking it", %{
      conn: conn,
      run: run,
      final_run: final_run,
      manifest_id: manifest_id,
      specification: specification
    } do
      pilot_schedule_run = EvaluationFixtures.completed_run(manifest_id)
      assert pilot_schedule_run.id != run.id

      expect_analysis(fn _bundle, _study_id, :pilot ->
        {:ok, EvaluationFixtures.pilot_eligible_archive()}
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: true})

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => [%{"tier" => "small", "run_id" => pilot_schedule_run.id}]
      })

      assert_reply(view, %{
        status: "rejected",
        mode: "final",
        errors: [%{code: "run_incompatible"}]
      })

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => final_selection(final_run)
      })

      assert_reply(view, %{status: "accepted", mode: "final"})
    end

    test "keeps a final retry on its locked mapping", %{
      conn: conn,
      run: run,
      final_run: final_run,
      specification: specification
    } do
      pilot_archive = EvaluationFixtures.pilot_eligible_archive()

      expect_analysis(fn _bundle, _study_id, mode ->
        case mode do
          :pilot -> {:ok, pilot_archive}
          :analyze -> {:error, :transport}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      study_event(view, "study_analysis_ready", %{mode: "pilot", pilot_eligible: true})

      final_payload = %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => final_selection(final_run)
      }

      render_hook(view, "start_study_analysis", final_payload)
      assert_reply(view, %{status: "accepted", mode: "final"})
      study_event(view, "study_analysis_error", %{mode: "final", error: %{code: "transport"}})

      render_hook(view, "start_study_analysis", final_payload)
      assert_reply(view, %{status: "accepted", mode: "final"})
      study_event(view, "study_analysis_error", %{mode: "final", error: %{code: "transport"}})

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "final",
        "tier_runs" => [%{"tier" => "small", "run_id" => Ecto.UUID.generate()}]
      })

      assert_reply(view, %{status: "rejected", errors: [%{code: "document_locked"}]})
    end
  end

  describe "close_study_document" do
    test "cancels a running task", %{conn: conn, run: run, specification: specification} do
      archive = EvaluationFixtures.pilot_eligible_archive()
      test_pid = self()

      expect_analysis(fn _bundle, _study_id, :pilot ->
        send(test_pid, {:analysis_started, self()})

        receive do
          :release -> {:ok, archive}
        after
          5_000 -> {:ok, archive}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()

      render_hook(view, "start_study_analysis", %{
        "document_id" => document_id,
        "specification_id" => specification.id,
        "mode" => "pilot",
        "tier_runs" => [%{"tier" => "small", "run_id" => run.id}]
      })

      assert_reply(view, %{status: "accepted"})
      assert_receive {:analysis_started, analysis_pid}, @timeout

      render_hook(view, "close_study_document", %{"document_id" => document_id})
      assert_reply(view, %{status: "closed"})

      wait_until(fn -> not Process.alive?(analysis_pid) end)
      refute Process.alive?(analysis_pid)

      render_hook(view, "close_study_document", %{"document_id" => document_id})
      assert_reply(view, %{status: "not_found"})

      render_hook(view, "close_study_document", %{"document_id" => "bad"})
      assert_reply(view, %{status: "invalid_request"})
    end

    test "terminate/2 cancels every owned task" do
      {:ok, pid} =
        Task.Supervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
          Process.sleep(:infinity)
        end)

      ref = Process.monitor(pid)
      document_id = Ecto.UUID.generate()

      session =
        StudySession.new(%{
          document_id: document_id,
          specification_id: Ecto.UUID.generate(),
          study_id: "topology-scale-study",
          specification_version: 1,
          tier_runs: [{"small", Ecto.UUID.generate()}]
        })
        |> StudySession.start_attempt(StudyAttempt.new(StudyAttempt.new_id(), :pilot, pid, ref))

      socket = %Phoenix.LiveView.Socket{
        assigns: %{study_sessions: %{document_id => session}}
      }

      assert :ok = DashboardLive.terminate(:shutdown, socket)

      wait_until(fn -> not Process.alive?(pid) end)
      refute Process.alive?(pid)
    end
  end

  defp single_tier_specification do
    EvaluationFixtures.study_specification() |> Map.put("tiers", ["small"])
  end

  defp warmup_run do
    manifest_id = "study-live-warmup-#{System.unique_integer([:positive])}"

    {:ok, _manifest} =
      EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.analysis_manifest())

    EvaluationFixtures.completed_run(manifest_id, "warmup")
  end

  defp incompatible_run do
    manifest_id = "study-live-incompatible-#{System.unique_integer([:positive])}"

    {:ok, _manifest} =
      EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.valid_manifest())

    EvaluationFixtures.completed_run(manifest_id)
  end

  defp expect_analysis(fun) do
    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, study_id, mode ->
      case fun.(bundle, study_id, mode) do
        {:ok, archive} -> {:ok, EvaluationFixtures.result_archive_for_bundle(archive, bundle)}
        error -> error
      end
    end)
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(fun, 0), do: assert(fun.())

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end
end
