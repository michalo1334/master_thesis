defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.MeasuredReplica.DAG do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.{
    PrepareReplica,
    RunPlan,
    RunSimulation,
    TimingBoundary
  }

  @positions 0..4

  defmacro tasks(position, options) when position in @positions do
    next_task = Keyword.fetch!(options, :next)
    names = task_names(position)

    quote do
      task_action unquote(names.prepare),
                  {unquote(PrepareReplica.Gust), [replica_position: unquote(position)]},
                  downstream: [unquote(names.plan_dispatch)],
                  store_result: true

      task_action unquote(names.plan_dispatch),
                  {unquote(TimingBoundary.Gust),
                   [replica_position: unquote(position), event: :plan_dispatch]},
                  downstream: [unquote(names.run_plan)]

      task_action unquote(names.run_plan), unquote(RunPlan.Gust),
        map_over: unquote(names.prepare),
        downstream: [unquote(names.plan_completion)]

      task_action unquote(names.plan_completion),
                  {unquote(TimingBoundary.Gust),
                   [replica_position: unquote(position), event: :plan_completion]},
                  downstream: [unquote(names.simulation_dispatch)]

      task_action unquote(names.simulation_dispatch),
                  {unquote(TimingBoundary.Gust),
                   [replica_position: unquote(position), event: :simulation_dispatch]},
                  downstream: [unquote(names.run_simulation)]

      task_action unquote(names.run_simulation), unquote(RunSimulation.Gust),
        map_over: unquote(names.prepare),
        downstream: [unquote(names.simulation_completion)]

      task_action unquote(names.simulation_completion),
                  {unquote(TimingBoundary.Gust),
                   [replica_position: unquote(position), event: :simulation_completion]},
                  downstream: [unquote(next_task)]
    end
  end

  defp task_names(position) do
    %{
      prepare: task_name(:prepare, position),
      plan_dispatch: task_name(:mark_plan_dispatch, position),
      run_plan: task_name(:run_plan, position),
      plan_completion: task_name(:mark_plan_completion, position),
      simulation_dispatch: task_name(:mark_simulation_dispatch, position),
      run_simulation: task_name(:run_simulation, position),
      simulation_completion: task_name(:mark_simulation_completion, position)
    }
  end

  # The position is a compile-time literal from the bounded @positions range.
  defp task_name(prefix, position), do: String.to_atom("#{prefix}_#{position}")
end
