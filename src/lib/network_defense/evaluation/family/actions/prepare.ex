defmodule NetworkDefense.Evaluation.Family.Actions.Prepare do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest}
  alias NetworkDefense.Evaluation.Family.{Member, TaskFailure}

  # Repeats family validation from persisted run parameters. The public API
  # already validated the request, but the task must not assume that persisted
  # parameters are valid.
  #
  # The nested comparison parser also runs here, so a persisted request with a
  # ragged matrix or a duplicate plan ID stops the run before any mapped task
  # exists.

  @impl true
  def execute(_args, %{run_id: run_id}) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> FamilyRequest.parse()
    |> case do
      {:ok, %FamilyRequest{} = request} -> items(request)
      {:error, error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp items(%FamilyRequest{} = request) do
    case Member.canonical_items(request) do
      {:ok, items} -> %{"gust_task_items" => items}
      {:error, %FamilyError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end
end
