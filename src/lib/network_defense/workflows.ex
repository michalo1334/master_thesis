defmodule NetworkDefense.Workflows do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Workflows.{StepWorker, WorkflowRun, WorkflowStep}

  @workflow_events_topic "workflow_events"

  @spec workflow_events_topic() :: String.t()
  def workflow_events_topic, do: @workflow_events_topic

  @spec start(String.t(), map(), keyword()) :: {:ok, WorkflowRun.t()} | {:error, term()}
  def start(template_name, input, opts \\ [])
      when is_binary(template_name) and is_map(input) and is_list(opts) do
    with {:ok, template} <- template_for(template_name) do
      case Keyword.fetch(opts, :correlation_id) do
        :error ->
          create_run(template_name, input, template.steps())

        {:ok, correlation_id} when is_binary(correlation_id) ->
          create_or_return_run(template_name, correlation_id, input, template.steps())

        {:ok, _correlation_id} ->
          {:error, :invalid_correlation_id}
      end
    end
  end

  def claim_step(run_id, position) do
    Repo.transaction(fn ->
      with %WorkflowRun{status: "running"} = run <- lock_run(run_id),
           %WorkflowStep{} = step <- lock_step(run_id, position),
           :ok <- ensure_claimable(step),
           {:ok, template} <- template_for(run.template) do
        step = step |> Ecto.Changeset.change(status: "running") |> Repo.update!()
        {template, run, step}
      else
        %WorkflowStep{status: "completed"} -> Repo.rollback(:completed)
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def prepare_step(template, %WorkflowRun{} = run, %WorkflowStep{} = step) do
    Repo.transaction(fn ->
      with %WorkflowStep{} = step <- lock_step(run.id, step.position),
           :ok <- ensure_claimable(step) do
        outputs = prior_outputs(run.id, step.position)
        prepare_resource(template, run, step, outputs)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def release_step(%WorkflowStep{} = step) do
    Repo.transaction(fn ->
      case lock_step(step.workflow_run_id, step.position) do
        %WorkflowStep{status: "running"} = locked ->
          locked |> Ecto.Changeset.change(status: "pending") |> Repo.update!()

        _ ->
          :ok
      end
    end)
  end

  def fail_step(%WorkflowRun{} = run, %WorkflowStep{} = step, reason) do
    error = format_error(reason)

    case Repo.transaction(fn -> mark_failed(run, step, error) end) do
      {:ok, failed_run} ->
        broadcast_failed(failed_run, reason)
        {:ok, failed_run}

      error ->
        error
    end
  end

  def complete_step(%WorkflowRun{} = run, %WorkflowStep{} = step, output) when is_map(output) do
    result =
      Repo.transaction(fn ->
        complete_locked_step(run, step, output)
      end)

    case result do
      {:ok, {:completed, completed_run}} ->
        broadcast_completed(completed_run)
        {:ok, completed_run}

      {:ok, result} ->
        {:ok, result}

      error ->
        error
    end
  end

  defp create_run(template_name, input, steps) do
    Repo.transaction(fn ->
      run =
        %WorkflowRun{}
        |> WorkflowRun.changeset(%{template: template_name, input: input})
        |> Repo.insert!()

      insert_steps_and_enqueue(run, steps)
      run
    end)
  end

  defp mark_failed(run, step, error) do
    case {lock_run(run.id), lock_step(run.id, step.position)} do
      {%WorkflowRun{status: "running"} = run, %WorkflowStep{} = step} ->
        step |> Ecto.Changeset.change(status: "failed", error: error) |> Repo.update!()
        run |> Ecto.Changeset.change(status: "failed", error: error) |> Repo.update!()

      {nil, _step} ->
        Repo.rollback(:not_found)

      {_run, nil} ->
        Repo.rollback(:not_found)

      {%WorkflowRun{}, %WorkflowStep{}} ->
        Repo.rollback(:not_running)
    end
  end

  defp complete_locked_step(run, step, output) do
    case lock_step(run.id, step.position) do
      %WorkflowStep{status: "completed"} ->
        :already_completed

      %WorkflowStep{} = step ->
        step =
          step |> Ecto.Changeset.change(status: "completed", output: output) |> Repo.update!()

        case next_step(run.id, step.position) do
          nil ->
            run = lock_run(run.id) |> Ecto.Changeset.change(status: "completed") |> Repo.update!()
            {:completed, run}

          next ->
            enqueue(run.id, next.position)
            :continued
        end

      nil ->
        Repo.rollback(:not_found)
    end
  end

  defp create_or_return_run(template_name, correlation_id, input, steps) do
    Repo.transaction(fn ->
      candidate =
        %WorkflowRun{}
        |> WorkflowRun.changeset(%{
          template: template_name,
          correlation_id: correlation_id,
          input: input
        })

      {:ok, candidate} =
        Repo.insert(candidate,
          on_conflict: :nothing,
          conflict_target: [:template, :correlation_id]
        )

      if Repo.exists?(from(run in WorkflowRun, where: run.id == ^candidate.id)) do
        insert_steps_and_enqueue(candidate, steps)
        candidate
      else
        Repo.get_by!(WorkflowRun, template: template_name, correlation_id: correlation_id)
      end
    end)
  end

  defp insert_steps_and_enqueue(run, steps) do
    Enum.with_index(steps, 1)
    |> Enum.each(fn {name, position} ->
      %WorkflowStep{}
      |> WorkflowStep.changeset(%{workflow_run_id: run.id, name: name, position: position})
      |> Repo.insert!()
    end)

    enqueue(run.id, 1)
  end

  defp enqueue(run_id, position) do
    case Oban.insert(StepWorker.new(%{"workflow_run_id" => run_id, "step_position" => position})) do
      {:ok, _job} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_claimable(%WorkflowStep{status: status}) when status in ["pending", "running"],
    do: :ok

  defp ensure_claimable(_step), do: {:error, :not_pending}

  defp prepare_resource(_template, _run, %WorkflowStep{resource_id: resource_id} = step, outputs)
       when is_binary(resource_id),
       do: {step, outputs}

  defp prepare_resource(template, run, step, outputs) do
    case template.prepare(step.name, Map.put(run.input, "analysis_id", run.id), outputs, nil) do
      {:ok, resource_id} ->
        step = step |> Ecto.Changeset.change(resource_id: resource_id) |> Repo.update!()
        {step, outputs}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp prior_outputs(run_id, position) do
    WorkflowStep
    |> where([step], step.workflow_run_id == ^run_id and step.position < ^position)
    |> order_by([step], asc: step.position)
    |> Repo.all()
    |> Map.new(&{&1.name, &1.output})
  end

  defp next_step(run_id, position) do
    WorkflowStep
    |> where([step], step.workflow_run_id == ^run_id and step.position == ^(position + 1))
    |> Repo.one()
  end

  defp lock_run(id),
    do: WorkflowRun |> where([run], run.id == ^id) |> lock("FOR UPDATE") |> Repo.one()

  defp lock_step(run_id, position) do
    WorkflowStep
    |> where([step], step.workflow_run_id == ^run_id and step.position == ^position)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp template_for(name) do
    case Application.get_env(:network_defense, :workflow_templates, %{}) do
      %{^name => template} -> {:ok, template}
      _ -> {:error, :unknown_template}
    end
  end

  defp broadcast_completed(%WorkflowRun{} = run) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @workflow_events_topic,
      {:workflow_completed, completion_payload(run)}
    )
  end

  defp broadcast_failed(%WorkflowRun{} = run, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @workflow_events_topic,
      {:workflow_failed, %{workflow_id: run.id, reason: reason}}
    )
  end

  defp completion_payload(run) do
    outputs =
      WorkflowStep
      |> where([step], step.workflow_run_id == ^run.id)
      |> Repo.all()
      |> Map.new(&{&1.name, &1.output || %{}})

    %{
      workflow_id: run.id,
      outputs: outputs
    }
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
