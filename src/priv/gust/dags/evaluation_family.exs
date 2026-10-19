defmodule NetworkDefense.Evaluation.Family.DAG do
  @moduledoc false
  use Gust.DSL

  alias NetworkDefense.Evaluation.Family.Actions.{CompareMember, CorrectFamily, Prepare}

  # Fixed family DAG: declare, map one member per declared identity, then
  # correct the complete family once.
  #
  # `map_over` expands the saved preparation items. Gust runs `correct_family`
  # only after every mapped member succeeds.

  task_action :prepare_family, {Prepare, []},
    downstream: [:compare_member],
    store_result: true

  task_action :compare_member, CompareMember,
    map_over: :prepare_family,
    ctx: %{params: params},
    downstream: [:correct_family],
    store_result: true do
    [item: params]
  end

  task_action :correct_family, {CorrectFamily, []}, store_result: true
end
