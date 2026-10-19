defmodule NetworkDefense.Evaluation.Comparison.Console do
  @moduledoc false

  alias NetworkDefense.Evaluation.GustConsole

  @fixtures %{
    "crossed-small" => "valid/crossed-small.request.json",
    "attack-column-count-mismatch" => "invalid/attack-column-count-mismatch.request.json"
  }

  def start!(start_application \\ &Application.ensure_all_started/1),
    do: GustConsole.start!(start_application)

  def fixture_path!(name) do
    case Map.fetch(@fixtures, name) do
      {:ok, relative_path} ->
        Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/#{relative_path}")

      :error ->
        Mix.raise("Unknown fixture #{inspect(name)}.")
    end
  end
end
