defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.MeasuredReplica.DAG do
  @moduledoc false

  # Declaration of one measured replica.
  #
  # A measured replica is the same seven-task chain at every position, so the
  # chain is written once and expanded at compile time. The expansion emits
  # ordinary `task_action` declarations: the checked-in DAG still owns the whole
  # graph, and Gust still reads one static definition per file.
  #
  # The position is a literal, so the generated task names and payload values are
  # compile-time values. Only the boundary after the last marker is a parameter,
  # because it differs between replicas.
  @measured_positions 0..4

  @doc """
  Declares the seven tasks of measured replica `position`.

  Generated tasks, in order: `prepare_<position>`, `mark_plan_dispatch_<position>`,
  `run_plan_<position>`, `mark_plan_completion_<position>`,
  `mark_simulation_dispatch_<position>`, `run_simulation_<position>`, and
  `mark_simulation_completion_<position>`.

  Options:

    * `:after` — the task that follows the last marker of this replica.
  """
  defmacro measured_replica(position, options) do
    unless position in @measured_positions do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "measured replica position must be 0..4, got: #{inspect(position)}"
    end

    after_task = Keyword.fetch!(options, :after)

    prepare = :"prepare_#{position}"
    plan_dispatch = :"mark_plan_dispatch_#{position}"
    plan = :"run_plan_#{position}"
    plan_completion = :"mark_plan_completion_#{position}"
    simulation_dispatch = :"mark_simulation_dispatch_#{position}"
    simulation = :"run_simulation_#{position}"
    simulation_completion = :"mark_simulation_completion_#{position}"

    quote do
      task_action unquote(prepare), unquote(adapter(:PrepareReplica)),
        ctx: %{run_id: run_id},
        downstream: [unquote(plan_dispatch)],
        store_result: true do
        [study_phase_run_id: phase_run_id(run_id), replica_position: unquote(position)]
      end

      task_action unquote(plan_dispatch), unquote(adapter(:TimingBoundary)),
        ctx: %{run_id: run_id},
        downstream: [unquote(plan)] do
        [
          study_phase_run_id: phase_run_id(run_id),
          replica_position: unquote(position),
          event_kind: :plan_dispatch
        ]
      end

      task_action unquote(plan), unquote(adapter(:RunPlan)),
        map_over: unquote(prepare),
        ctx: %{params: params},
        downstream: [unquote(plan_completion)] do
        [collection_item_id: params["collection_item_id"]]
      end

      task_action unquote(plan_completion), unquote(adapter(:TimingBoundary)),
        ctx: %{run_id: run_id},
        downstream: [unquote(simulation_dispatch)] do
        [
          study_phase_run_id: phase_run_id(run_id),
          replica_position: unquote(position),
          event_kind: :plan_completion
        ]
      end

      task_action unquote(simulation_dispatch), unquote(adapter(:TimingBoundary)),
        ctx: %{run_id: run_id},
        downstream: [unquote(simulation)] do
        [
          study_phase_run_id: phase_run_id(run_id),
          replica_position: unquote(position),
          event_kind: :simulation_dispatch
        ]
      end

      task_action unquote(simulation), unquote(adapter(:RunSimulation)),
        map_over: unquote(prepare),
        ctx: %{params: params},
        downstream: [unquote(simulation_completion)] do
        [collection_item_id: params["collection_item_id"]]
      end

      task_action unquote(simulation_completion), unquote(adapter(:TimingBoundary)),
        ctx: %{run_id: run_id},
        downstream: [unquote(after_task)] do
        [
          study_phase_run_id: phase_run_id(run_id),
          replica_position: unquote(position),
          event_kind: :simulation_completion
        ]
      end
    end
  end

  defp adapter(step) do
    Module.concat([
      NetworkDefense.Evaluation.Study.Pipeline.Final.Collection,
      step,
      Gust
    ])
  end
end
