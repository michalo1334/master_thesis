defmodule NetworkDefense.Compute.ProgressTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.Progress

  test "PROGRESS-01: returns ok for any non-error callback result" do
    progress = %{completed: 2, total: 5}

    assert :ok = Progress.report(fn update -> send(self(), {:progress, update}) end, progress)
    assert_received {:progress, ^progress}
  end

  test "PROGRESS-02: preserves callback error tuples" do
    assert {:error, :stopped} = Progress.report(fn _progress -> {:error, :stopped} end, %{})
  end

  test "PROGRESS-03: converts raised and caught callback failures to errors" do
    assert {:error, %RuntimeError{message: "failed"}} =
             Progress.report(fn _progress -> raise "failed" end, %{})

    assert {:error, {:throw, :stopped}} =
             Progress.report(fn _progress -> throw(:stopped) end, %{})

    assert {:error, {:exit, :stopped}} =
             Progress.report(fn _progress -> exit(:stopped) end, %{})
  end
end
