defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Binding
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.{Request, Result}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.{IO, RequestBuilder, Workflow}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError
  alias NetworkDefense.Evaluation.Study.Pipeline.Result, as: CompactResult
  alias NetworkDefense.Evaluation.Study.Pipeline.Result.Store
  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.StudyPhase

  # The Final analysis stage.
  #
  # The stage accepts one Gust run, dispatches it, waits for it, and stores the
  # compact successful result. Every database mutation runs under the execution
  # lock; the wait itself holds no lock.
  #
  # A repeated entry into the same analysis reuses the accepted run and the
  # persisted handoff. Awaiting is authoritative only through the persisted Gust
  # status, and a cancellation that commits during the wait cannot store a result
  # or revive the execution.
  #
  # The boundary exposes study-level outcomes only: completion, a stop, or one
  # bounded study error.
  @defaults [workflow: Workflow, timeout: :infinity]

  @spec run(IO.t(), keyword()) ::
          {:ok, :completed} | {:stop, atom()} | {:error, StudyError.t()}
  def run(%IO{} = io, opts \\ []) do
    options = Keyword.merge(@defaults, opts)
    workflow = options[:workflow]
    timeout = options[:timeout]

    result =
      with {:ok, io} <- hydrate(io),
           {:ok, run_id} <- ensure_run(io, workflow),
           :ok <- State.accept_run(io.execution.id, :analyzing_final, io.phase, run_id),
           :ok <-
             State.dispatch_run(io.execution.id, :analyzing_final, io.phase, run_id, workflow),
           {:ok, :succeeded} <- workflow.await(run_id, timeout),
           :ok <- State.require_state(io.execution.id, :analyzing_final),
           {:ok, %Result{} = final_result} <- workflow.result(run_id),
           {:ok, %CompactResult{} = compact} <-
             Store.create_success(io.execution, final_result, io.timing) do
        {:ok, %{io | result: final_result, compact_result: compact}}
      end

    stage_result(result)
  end

  defp stage_result({:ok, %IO{}}), do: {:ok, :completed}
  defp stage_result({:stop, state}), do: {:stop, state}
  defp stage_result({:error, %StudyError{} = error}), do: {:error, error}

  defp stage_result({:error, %FinalError{}}), do: {:error, StudyError.final_analysis_failed()}
  defp stage_result(_unexpected), do: {:error, StudyError.final_analysis_failed()}

  # The request is built once. A stage entered from collection already carries
  # the snapshot and timing; a resumed stage rebuilds the same typed request from
  # the persisted study and re-verifies the snapshot binding.
  defp hydrate(%IO{request: %Request{} = request} = io) do
    case Binding.verify(request) do
      {:ok, payload} -> {:ok, %{io | payload: payload}}
      {:error, %FinalError{} = error} -> {:error, error}
    end
  end

  defp hydrate(%IO{execution: execution, snapshot_id: snapshot_id} = io) do
    with {:ok, request} <- RequestBuilder.build(execution.id, snapshot_id),
         {:ok, payload} <- Binding.verify(request) do
      {:ok, %{io | request: request, payload: payload}}
    end
  end

  # One accepted run per analysis phase. A resumed stage reuses the stored run
  # only when it carries the same request, so a changed declaration cannot be
  # analyzed by an older run.
  defp ensure_run(%IO{phase: %StudyPhase{gust_run_id: nil}} = io, workflow) do
    create_run(io, workflow)
  end

  defp ensure_run(
         %IO{phase: %StudyPhase{gust_run_id: run_id}, request: %Request{} = request},
         workflow
       ) do
    workflow.verify_request(run_id, request)
  end

  defp create_run(%IO{request: %Request{} = request}, workflow), do: workflow.create(request)
end
