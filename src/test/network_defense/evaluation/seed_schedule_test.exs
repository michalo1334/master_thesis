defmodule NetworkDefense.Evaluation.SeedScheduleTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.SeedSchedule

  test "explicit optimizer settings override the attack trial fallback" do
    manifest = %{
      "evaluation" => %{
        "trials" => 10,
        "seed" => 9001,
        "optimizer_trials" => 20,
        "optimizer_iterations" => 5
      },
      "attacker" => %{"max_attempts" => 1}
    }

    schedule = SeedSchedule.build(manifest, "entry")

    assert schedule.optimizer_trials == 20
    assert schedule.optimizer_iterations == 5
  end

  test "old manifests fall back to attack trials and one iteration" do
    manifest = %{
      "evaluation" => %{"trials" => 7, "seed" => 9001},
      "attacker" => %{"max_attempts" => 1}
    }

    schedule = SeedSchedule.build(manifest, "entry")

    assert schedule.optimizer_trials == 7
    assert schedule.optimizer_iterations == 1
  end
end
