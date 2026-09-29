Code.require_file(Path.expand("../../../credo/checks/error_codes_match_type.ex", __DIR__))

defmodule NetworkDefense.Credo.ErrorCodesMatchTypeTest do
  use ExUnit.Case, async: false

  alias Credo.SourceFile
  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Credo.ErrorCodesMatchType
  alias NetworkDefense.Repo

  test "loads application modules before checking a remote code union" do
    was_started? = application_started?(:network_defense)
    unload_network_defense(was_started?)

    assert Application.spec(:network_defense, :modules) == nil

    source_file =
      "lib/network_defense/errors.ex"
      |> File.read!()
      |> SourceFile.parse("lib/network_defense/errors.ex")

    assert ErrorCodesMatchType.run(source_file, []) == []
    assert is_list(Application.spec(:network_defense, :modules))
  end

  defp unload_network_defense(was_started?) do
    Application.ensure_all_started(:credo)

    if was_started? do
      :ok = Application.stop(:network_defense)
    end

    :ok = Application.unload(:network_defense)

    on_exit(fn -> restore_network_defense(was_started?) end)
  end

  defp restore_network_defense(true) do
    :ok = Application.unload(:network_defense)
    {:ok, _applications} = Application.ensure_all_started(:network_defense)
    Sandbox.mode(Repo, :manual)
  end

  defp restore_network_defense(false), do: Application.load(:network_defense)

  defp application_started?(application) do
    Enum.any?(Application.started_applications(), fn {name, _description, _version} ->
      name == application
    end)
  end
end
