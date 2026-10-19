defmodule NetworkDefense.Evaluation.Family.Console do
  @moduledoc false

  alias NetworkDefense.Evaluation.GustConsole

  @root "priv/evaluation/family/v1"

  @fixtures %{
    "holm-small" => "valid/holm-small.request.json",
    "duplicate-expected-identity" => "invalid/duplicate-expected-identity.request.json",
    "duplicate-comparison-identity" => "invalid/duplicate-comparison-identity.request.json",
    "missing-comparison" => "invalid/missing-comparison.request.json",
    "unexpected-comparison" => "invalid/unexpected-comparison.request.json",
    "identity-mismatch" => "invalid/identity-mismatch.request.json",
    "nested-attack-column-mismatch" => "invalid/nested-attack-column-mismatch.request.json",
    "nested-duplicate-plan-id" => "invalid/nested-duplicate-plan-id.request.json",
    "unsupported-method" => "invalid/unsupported-method.request.json"
  }

  def start!(start_application \\ &Application.ensure_all_started/1),
    do: GustConsole.start!(start_application)

  def fixture_path!(name) do
    case Map.fetch(@fixtures, name) do
      {:ok, relative_path} ->
        Application.app_dir(:network_defense, Path.join(@root, relative_path))

      :error ->
        Mix.raise("Unknown fixture #{inspect(name)}.")
    end
  end

  def names, do: @fixtures |> Map.keys() |> Enum.sort()
end
