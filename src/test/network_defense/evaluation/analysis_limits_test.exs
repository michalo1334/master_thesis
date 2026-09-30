defmodule NetworkDefense.Evaluation.AnalysisLimitsTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.AnalysisLimits

  setup do
    previous = Application.get_env(:network_defense, :analysis_service)
    on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)
    :ok
  end

  describe "max_zip_bytes/0" do
    test "uses a configured positive integer" do
      put_limits(max_zip_bytes: 1234)

      assert AnalysisLimits.max_zip_bytes() == 1234
    end

    test "falls back to the default for zero, negative, and non-integer values" do
      for value <- [0, -1, "10", 1.5, :infinity, nil] do
        put_limits(max_zip_bytes: value)

        assert AnalysisLimits.max_zip_bytes() == AnalysisLimits.default_max_zip_bytes()
      end
    end
  end

  describe "browser_result_bytes/0" do
    test "uses a configured positive integer below the service maximum" do
      put_limits(max_zip_bytes: 10_000, browser_result_bytes: 1000)

      assert AnalysisLimits.browser_result_bytes() == 1000
    end

    test "never exceeds the service maximum" do
      put_limits(max_zip_bytes: 1000, browser_result_bytes: 2000)

      assert AnalysisLimits.browser_result_bytes() == 1000

      assert AnalysisLimits.browser_result_bytes() <= AnalysisLimits.max_zip_bytes()
    end

    test "falls back to the default for zero, negative, and non-integer values" do
      for value <- [0, -5, "1MB", 2.5, :unlimited, nil] do
        put_limits(max_zip_bytes: 10_000_000, browser_result_bytes: value)

        assert AnalysisLimits.browser_result_bytes() ==
                 AnalysisLimits.default_browser_result_bytes()
      end
    end

    test "clamps a malformed value to a small service maximum" do
      put_limits(max_zip_bytes: 1000, browser_result_bytes: 0)

      assert AnalysisLimits.browser_result_bytes() == 1000
    end

    test "keeps the default browser limit below the default service maximum" do
      put_limits([])

      assert AnalysisLimits.browser_result_bytes() < AnalysisLimits.max_zip_bytes()
    end
  end

  describe "browser_deliverable?/1" do
    test "accepts the limit and rejects one byte more" do
      put_limits(browser_result_bytes: 8)

      assert AnalysisLimits.browser_deliverable?(:binary.copy(<<0>>, 8))
      refute AnalysisLimits.browser_deliverable?(:binary.copy(<<0>>, 9))
      refute AnalysisLimits.browser_deliverable?(:not_a_binary)
    end
  end

  defp put_limits(pairs) do
    Application.put_env(:network_defense, :analysis_service, pairs)
  end
end
