defmodule NetworkDefense.Evaluation.Study.Pipeline.Coordinator do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Runner

  @task_supervisor NetworkDefense.TaskSupervisor

  @spec start(Ecto.UUID.t()) :: {:ok, pid()} | {:error, term()}
  def start(execution_id) do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      Runner.run(execution_id)
    end)
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.Runner do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.{ExecutionAccess, Final, Pilot}

  @terminal_states [:awaiting_final, :succeeded, :failed, :cancelled]

  @spec run(Ecto.UUID.t(), keyword()) :: :ok | {:error, term()}
  def run(execution_id, options \\ []) do
    with {:ok, execution} <- ExecutionAccess.fetch(execution_id) do
      run_state(execution, options)
    end
  end

  defp run_state(%{state: :collecting_pilot} = execution, options) do
    with {:ok, collection_io} <- Pilot.Collection.IO.load(execution.id),
         {:ok, analysis_io} <- Pilot.Collection.run(collection_io, options),
         {:ok, :paused} <- Pilot.Analysis.run(analysis_io, options) do
      :ok
    end
  end

  defp run_state(%{state: :collecting_final} = execution, options) do
    with {:ok, collection_io} <- Final.Collection.IO.load(execution.id),
         {:ok, analysis_io} <- Final.Collection.run(collection_io, options),
         {:ok, :completed} <- Final.Analysis.run(analysis_io, options) do
      :ok
    end
  end

  defp run_state(%{state: :analyzing_final} = execution, options) do
    with {:ok, analysis_io} <- Final.Analysis.IO.load(execution.id),
         {:ok, :completed} <- Final.Analysis.run(analysis_io, options) do
      :ok
    end
  end

  defp run_state(%{state: state}, _options) when state in @terminal_states, do: :ok
end
