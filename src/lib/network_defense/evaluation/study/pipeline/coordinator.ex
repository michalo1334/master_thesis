defmodule NetworkDefense.Evaluation.Study.Pipeline.Coordinator do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Runner

  @coordinator_registry NetworkDefense.Evaluation.Study.Pipeline.CoordinatorRegistry
  @start_timeout 5_000

  @spec start(Ecto.UUID.t()) :: {:ok, pid()} | {:error, StudyError.t()}
  def start(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, id} -> start_coordinator(id)
      :error -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp start_coordinator(execution_id) do
    caller = self()
    handshake = make_ref()

    case Task.Supervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
           claim_and_run(caller, handshake, execution_id, [])
         end) do
      {:ok, pid} -> await_start(pid, handshake)
      {:error, _reason} -> {:error, StudyError.coordinator_not_startable()}
    end
  end

  defp claim_and_run(caller, handshake, execution_id, opts) do
    case Registry.register(@coordinator_registry, execution_id, nil) do
      {:ok, _owner} ->
        case Runner.prepare(execution_id) do
          {:ok, _execution, _phase} ->
            send(caller, {:coordinator_claimed, handshake, self()})

            receive do
              {:run_coordinator, ^handshake} -> Runner.run(execution_id, opts)
            after
              @start_timeout -> :ok
            end

          {:stop, _state} ->
            send(caller, {:coordinator_start_error, handshake, self(), start_error()})

          {:error, %StudyError{} = error} ->
            send(caller, {:coordinator_start_error, handshake, self(), error})
        end

      {:error, {:already_registered, _pid}} ->
        send(caller, {:coordinator_start_error, handshake, self(), start_error()})
    end
  end

  defp await_start(pid, handshake) do
    monitor = Process.monitor(pid)

    receive do
      {:coordinator_claimed, ^handshake, ^pid} ->
        Process.demonitor(monitor, [:flush])
        send(pid, {:run_coordinator, handshake})
        {:ok, pid}

      {:coordinator_start_error, ^handshake, ^pid, %StudyError{} = error} ->
        Process.demonitor(monitor, [:flush])
        {:error, error}

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        {:error, start_error()}
    after
      @start_timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, start_error()}
    end
  end

  defp start_error, do: StudyError.coordinator_not_startable()
end
