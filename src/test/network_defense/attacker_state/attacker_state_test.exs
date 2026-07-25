defmodule NetworkDefense.AttackerState.AttackerStateTest do
  use ExUnit.Case, async: true

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

  describe "to_map/from_map roundtrip" do
    test "roundtrips all fields" do
      state =
        AttackerState.new("host-1", :administrator)
        |> AttackerState.add_foothold("host-2", :user)
        |> AttackerState.add_credential("cred-1")
        |> AttackerState.mark_attempted({:test, "key"})

      map = AttackerState.to_map(state)
      {:ok, restored} = AttackerState.from_map(map)

      assert AttackerState.foothold_nodes(restored) |> Enum.sort() == ["host-1", "host-2"]
      assert AttackerState.privilege_for(restored, "host-1") == :administrator
      assert AttackerState.privilege_for(restored, "host-2") == :user
      assert AttackerState.has_credential?(restored, "cred-1")
      assert AttackerState.attempted?(restored, {:test, "key"})
    end

    test "legacy state map derives user privileges for footholds and empty credentials" do
      legacy_map = %{
        "footholds" => ["host-1", "host-2"],
        "attempted_actions" => []
      }

      {:ok, state} = AttackerState.from_map(legacy_map)
      assert AttackerState.privilege_for(state, "host-1") == :user
      assert AttackerState.privilege_for(state, "host-2") == :user
      refute AttackerState.has_credential?(state, "anything")
    end

    test "rejects invalid maps" do
      assert AttackerState.from_map(%{}) == :error

      assert AttackerState.from_map(%{"footholds" => "not_a_list", "attempted_actions" => []}) ==
               :error
    end
  end
end
