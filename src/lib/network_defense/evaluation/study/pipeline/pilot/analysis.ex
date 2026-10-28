defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Contracts.PilotResult

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.{
    IO,
    Outcome,
    Preflight,
    RequestBuilder,
    Workflow
  }

  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Repo

  # Runs the Pilot analysis stage of one study execution.
  #
  # The stage accepts the handoff from Pilot collection, drives one Gust run, and
  # owns its successful transition. Waiting for Gust stays outside every
  # database lock, so a cancellation is never blocked by a long run. A run that
  # completes after cancellation persists nothing.
  @phase :pilot_analysis
  @active_state :analyzing_pilot

  @spec run(IO.t(), keyword()) ::
          {:ok, :paused} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{} = io, opts \\ []) do
    workflow = Keyword.get(opts, :workflow, Workflow)

    with {:ok, request} <- RequestBuilder.build(io.execution, io.definition, io.snapshot_id),
         :ok <- Preflight.validate(request),
         {:ok, run_id} <- workflow.create(request),
         :ok <- State.accept_run(io.execution.id, @active_state, io.phase, run_id),
         :ok <- State.dispatch_run(io.execution.id, @active_state, io.phase, run_id, workflow),
         {:ok, :succeeded} <- workflow.await(run_id),
         {:ok, %PilotResult{} = result} <- workflow.result(run_id),
         {:ok, outcome} <- Outcome.from_result(result) do
      persist(%{io | request: request, result: result, outcome: outcome})
    end
    |> bounded()
  end

  # One transaction stores the compact outcome, links it to the analysis phase,
  # and moves the execution to the Final gate.
  defp persist(%IO{execution: %StudyExecution{id: execution_id}, outcome: %Outcome{} = outcome}) do
    params = Outcome.to_params(outcome)

    State.transaction(execution_id, fn execution ->
      if execution.state == @active_state do
        phase = State.lock_named_phase(execution.id, @phase)
        State.update_phase!(phase, %{result_ref: params})

        execution
        |> StudyExecution.changeset(%{pilot_outcome: params})
        |> Repo.update!()
        |> State.transition!(:pilot_analyzed)

        {:ok, :paused}
      else
        State.stop(execution.state)
      end
    end)
  end

  # The stage exposes study failures only. Pilot failures stay bounded inside the
  # pilot boundary.
  defp bounded({:ok, :paused} = paused), do: paused
  defp bounded({:stop, state}), do: {:stop, state}
  defp bounded({:error, %StudyError{} = error}), do: {:error, error}
  defp bounded({:error, _pilot_error}), do: {:error, StudyError.pilot_analysis_failed()}
end
