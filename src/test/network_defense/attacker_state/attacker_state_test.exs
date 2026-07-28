defmodule NetworkDefense.AttackerState.AttackerStateTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.AcquireCredential
  alias NetworkDefense.AttackerState.AttackerState

  describe "new/2" do
    test "creates state with default user privilege" do
      state = AttackerState.new("host-1")
      assert AttackerState.foothold_nodes(state) == ["host-1"]
      assert AttackerState.privilege_for(state, "host-1") == :user
      assert AttackerState.has_privilege?(state, "host-1", :user)
      refute AttackerState.has_privilege?(state, "host-1", :administrator)
    end

    test "creates state with specified privilege" do
      state = AttackerState.new("host-1", :administrator)
      assert AttackerState.privilege_for(state, "host-1") == :administrator
      assert AttackerState.has_privilege?(state, "host-1", :administrator)
    end
  end

  describe "add_foothold/3 privilege upgrades" do
    test "adds foothold with default user privilege" do
      state = AttackerState.new("host-1")
      state = AttackerState.add_foothold(state, "host-2")
      assert "host-2" in AttackerState.foothold_nodes(state)
      assert AttackerState.privilege_for(state, "host-2") == :user
    end

    test "upgrades privilege when higher one is provided" do
      state = AttackerState.new("host-1", :user)
      state = AttackerState.add_foothold(state, "host-1", :administrator)
      assert AttackerState.privilege_for(state, "host-1") == :administrator
    end

    test "does not downgrade privilege" do
      state = AttackerState.new("host-1", :administrator)
      state = AttackerState.add_foothold(state, "host-1", :user)
      assert AttackerState.privilege_for(state, "host-1") == :administrator
    end
  end

  describe "privilege_for/2 and has_privilege?/3" do
    test "returns :none for unknown host" do
      state = AttackerState.new("host-1")
      assert AttackerState.privilege_for(state, "unknown") == :none
      refute AttackerState.has_privilege?(state, "unknown", :user)
    end

    test "partial order: none < user < administrator" do
      state = AttackerState.new("host-1", :user)
      refute AttackerState.has_privilege?(state, "host-1", :administrator)
      assert AttackerState.has_privilege?(state, "host-1", :user)
      assert AttackerState.has_privilege?(state, "host-1", :none)
    end
  end

  describe "credential operations" do
    test "add and check credentials" do
      state = AttackerState.new("host-1")
      state = AttackerState.add_credential(state, "cred-1")
      assert AttackerState.has_credential?(state, "cred-1")
      refute AttackerState.has_credential?(state, "cred-2")
    end
  end

  describe "attempted actions" do
    test "tracks complete action structs" do
      action = %AcquireCredential{credential_id: "cred-1", host_id: "host-1"}
      state = AttackerState.new("host-1") |> AttackerState.mark_attempted(action, 2)

      assert AttackerState.attempted?(state, action)
    end
  end
end
