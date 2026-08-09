defmodule NetworkDefense.Actions.AttemptedActionTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.{
    AcquireCredential,
    AttemptedAction,
    ExploitVulnerability,
    ReuseCredential
  }

  test "round-trips every registered attempted action type" do
    actions = [%ExploitVulnerability{}, %AcquireCredential{}, %ReuseCredential{}]

    assert Enum.all?(actions, fn action ->
             action
             |> AttemptedAction.new()
             |> AttemptedAction.action()
             |> Kernel.==(action)
           end)
  end
end
