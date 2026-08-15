defmodule NetworkDefense.WorkflowTemplates.TwoStep do
  @moduledoc false

  @behaviour NetworkDefense.Workflows.Template

  alias NetworkDefense.Repo

  @impl true
  def steps, do: ["first", "second"]

  @impl true
  def prepare(_step, _input, _outputs, resource_id) when is_binary(resource_id),
    do: {:ok, resource_id}

  def prepare("first", _input, _outputs, nil) do
    send(self(), {:workflow_template_prepare, "first", Repo.in_transaction?()})
    {:ok, "first-resource"}
  end

  def prepare("second", %{"fail_second_prepare" => true}, _outputs, nil),
    do: {:error, :prepare_failed}

  def prepare("second", _input, _outputs, nil) do
    send(self(), {:workflow_template_prepare, "second", Repo.in_transaction?()})
    {:ok, "second-resource"}
  end

  @impl true
  def run_or_resume("first", _input, _outputs, "first-resource") do
    send(self(), {:workflow_template, "first"})
    {:ok, %{"value" => "first"}}
  end

  def run_or_resume("second", %{"fail_second_once" => true}, _outputs, "second-resource") do
    attempts = Process.get(:two_step_attempts, 0)
    Process.put(:two_step_attempts, attempts + 1)

    if attempts == 0 do
      {:error, :transient_failure}
    else
      {:ok, %{"value" => "second"}}
    end
  end

  def run_or_resume("second", %{"fail_second_always" => true}, _outputs, "second-resource"),
    do: {:error, :internal_error}

  def run_or_resume("second", %{"terminate_second" => "exit"}, _outputs, "second-resource"),
    do: exit(:template_exit)

  def run_or_resume("second", %{"terminate_second" => "throw"}, _outputs, "second-resource"),
    do: throw(:template_throw)

  def run_or_resume("second", _input, _outputs, "second-resource"),
    do: {:ok, %{"value" => "second"}}
end
