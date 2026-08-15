defmodule NetworkDefense.Workflows.StepWorker do
  @moduledoc false

  use Oban.Worker, queue: :workflows, max_attempts: 3

  alias NetworkDefense.Workflows

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_run_id" => run_id, "step_position" => position}} = job) do
    case Workflows.claim_step(run_id, position) do
      {:ok, {template, run, step}} ->
        settle({run, step}, job, run_step(template, run, step))

      {:error, :completed} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp run_step(template, run, step) do
    try do
      with {:ok, {step, outputs}} <- Workflows.prepare_step(template, run, step),
           {:ok, output} <-
             template.run_or_resume(step.name, run.input, outputs, step.resource_id),
           {:ok, _} <- Workflows.complete_step(run, step, output) do
        :ok
      end
    rescue
      error -> {:error, Exception.message(error)}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp settle(_step, _job, :ok), do: :ok

  defp settle(
         {run, step},
         %Oban.Job{attempt: attempt, max_attempts: max_attempts},
         {:error, reason}
       ) do
    if attempt >= max_attempts do
      Workflows.fail_step(run, step, reason)
      {:error, reason}
    else
      Workflows.release_step(step)
      {:error, reason}
    end
  end
end
