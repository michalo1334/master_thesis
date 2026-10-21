defmodule NetworkDefense.Evaluation.Final.Actions.PrepareFinal do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Final.{Member, TaskFailure}

  # Preparation repeats the strict Final contract and every cross-boundary
  # relation from persisted run parameters. The public API already validated
  # the request, but the task must not assume that persisted parameters are
  # valid.
  #
  # The stored items are compact: a position and a declared identity. Evidence
  # matrices stay in PostgreSQL. Preparation runs before any mapped comparison
  # task exists, so a contract, snapshot, source-Pilot, resource, or count
  # violation stops the run with no member result.

  @impl true
  def execute(_args, %{run_id: run_id}) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> prepare()
    |> case do
      {:ok, %{"gust_task_items" => _items} = result} -> result
      {:error, %FinalError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp prepare(params) do
    with {:ok, %Request{} = request} <- Request.parse(params),
         {:ok, payload} <- Binding.verify(request),
         :ok <- Member.preflight(request, payload) do
      {:ok, %{"gust_task_items" => Member.declared_items(request)}}
    end
  end
end
