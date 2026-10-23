defmodule Mix.Tasks.Evaluate.OptionsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Evaluate.Options

  test "EVALUATE-OPTIONS-01: accepts all required options" do
    assert :ok = Options.validate([manifest_id: "manifest"], [], [], [:manifest_id])
  end

  test "EVALUATE-OPTIONS-02: reports the first missing option in declaration order" do
    assert {:error, "missing required option --run-id"} =
             Options.validate([output: "result.zip"], [], [], [:run_id, :output])

    assert {:error, "missing required option --frozen-manifest-id"} =
             Options.validate(
               [manifest_id: "source"],
               [],
               [],
               [:manifest_id, :frozen_manifest_id]
             )
  end

  test "EVALUATE-OPTIONS-03: reports positional and parser errors before missing options" do
    assert {:error, "invalid options: extra, unknown"} =
             Options.validate([], ["extra"], [{:unknown, nil}], [:manifest_id])
  end
end
