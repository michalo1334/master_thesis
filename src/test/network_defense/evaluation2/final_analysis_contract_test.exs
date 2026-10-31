defmodule NetworkDefense.Evaluation2.FinalAnalysisContractTest do
  @moduledoc """
  Strict Gust transport of the Final analysis phase.

  The run input and the terminal result cross the Gust JSON boundary, so every
  case exercises the stored shape: string keys, canonical UUID strings, and JSON
  scalar types. The corrected family keeps the declared comparison order, and one
  unusable comparison rejects the whole family.

  The cases need no database, because the codecs are the whole subject.

      mix test test/network_defense/evaluation2/final_analysis_contract_test.exs
  """

  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag case_id: "RESULT-02/BIND-02"

  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract.{Input, Output}
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily

  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{
    Adjustment,
    Assessment,
    Estimate,
    Interval,
    Statistics,
    Test
  }

  @phase_run_id "9be1c5d2-3f24-4a51-9a9b-0d3bf5cc0f4e"
  @snapshot_id "1ac0d6f0-6e5c-4d2f-8f18-2b7a6e0b5c11"

  describe "Input" do
    test "the canonical input round trips through JSON-safe parameters" do
      input = %Input{phase_run_id: @phase_run_id, snapshot_id: @snapshot_id}

      params = AnalysisContract.to_params(input)

      assert params == %{
               "study_phase_run_id" => @phase_run_id,
               "study_evidence_snapshot_id" => @snapshot_id
             }

      assert {:ok, ^input} = AnalysisContract.decode_input(params)
    end

    test "the input codec rejects non-canonical, missing, and foreign parameters" do
      for params <- [
            %{},
            %{"study_phase_run_id" => @phase_run_id},
            %{"study_evidence_snapshot_id" => @snapshot_id},
            %{
              "study_phase_run_id" => @phase_run_id,
              "study_evidence_snapshot_id" => String.upcase(@snapshot_id)
            },
            %{
              "study_phase_run_id" => "not-a-uuid",
              "study_evidence_snapshot_id" => @snapshot_id
            },
            %{
              "study_phase_run_id" => @phase_run_id,
              "study_evidence_snapshot_id" => @snapshot_id,
              "unexpected" => 1
            },
            %{"study_phase_id" => @phase_run_id, "snapshot_id" => @snapshot_id},
            []
          ] do
        assert :error = AnalysisContract.decode_input(params)
      end
    end
  end

  describe "Output" do
    test "the corrected family round trips in declared comparison order" do
      output = %Output{family_result: family([comparison(0), comparison(1)])}

      assert {:ok, params} = AnalysisContract.encode_output(output)
      assert {:ok, ^output} = AnalysisContract.decode_output(params)
      assert ^output = AnalysisContract.decode_output!(params)

      comparisons = params["family_result"]["comparisons"]
      assert [first, second] = comparisons
      assert first["statistics"]["method"] == "matching_bounded_mean_v1"
      assert second["adjustment"]["reject_null"] == true
    end

    test "a non-informative comparison keeps its warning and conservative interval" do
      uninformative = %Assessment{status: :non_informative, warnings: [:empty_inversion]}

      output = %Output{
        family_result:
          family([%{comparison(0) | statistics: %{statistics(0) | assessment: uninformative}}])
      }

      assert {:ok, params} = AnalysisContract.encode_output(output)
      assert {:ok, decoded} = AnalysisContract.decode_output(params)
      assert decoded == output

      assessment =
        params["family_result"]["comparisons"]
        |> hd()
        |> get_in(["statistics", "assessment"])

      assert assessment == %{"status" => "non_informative", "warnings" => ["empty_inversion"]}
    end

    test "an integral JSON number decodes to the declared float type" do
      {:ok, params} =
        AnalysisContract.encode_output(%Output{family_result: family([comparison(0)])})

      [stored] = params["family_result"]["comparisons"]
      integral = put_in(stored, ["statistics", "test", "raw_p_value"], 0)

      assert {:ok, %Output{family_result: %CorrectedFamily{comparisons: [decoded]}}} =
               AnalysisContract.decode_output(%{
                 "family_result" => %{"comparisons" => [integral]}
               })

      assert decoded.statistics.test.raw_p_value === 0.0
    end

    test "the output codec rejects a family outside the declared shape" do
      {:ok, params} =
        AnalysisContract.encode_output(%Output{family_result: family([comparison(0)])})

      [stored] = params["family_result"]["comparisons"]

      for stored_family <- [
            %{},
            %{"comparisons" => []},
            %{"comparisons" => :none},
            %{"comparisons" => [%{}]},
            %{"comparisons" => [Map.delete(stored, "adjustment")]},
            %{"comparisons" => [stored, %{}]},
            %{"comparisons" => [stored], "unexpected" => 1}
          ] do
        assert :error = AnalysisContract.decode_output(%{"family_result" => stored_family})
      end

      assert :error = AnalysisContract.decode_output(%{"family" => family_params(params)})
      assert :error = AnalysisContract.decode_output([])
    end

    test "the family codec rejects a partially valid comparison" do
      {:ok, params} =
        AnalysisContract.encode_output(%Output{family_result: family([comparison(0)])})

      [stored] = params["family_result"]["comparisons"]

      for update <- [
            &put_in(&1, ["statistics", "method"], "unknown_method"),
            &put_in(&1, ["statistics", "estimate", "contrast"], "reference_minus_alternative"),
            &put_in(&1, ["statistics", "interval", "lower"], 0.9),
            &put_in(&1, ["statistics", "interval", "confidence_level"], 1.5),
            &put_in(&1, ["statistics", "test", "alternative"], "one_sided"),
            &put_in(&1, ["statistics", "test", "raw_p_value"], -0.1),
            &put_in(&1, ["statistics", "assessment", "status"], "unknown_status"),
            &put_in(&1, ["statistics", "assessment", "warnings"], ["unknown_warning"]),
            &put_in(&1, ["statistics", "assessment", "warnings"], [1]),
            &put_in(&1, ["adjustment", "adjusted_p_value"], 1.2),
            &put_in(&1, ["adjustment", "reject_null"], "false"),
            &put_in(&1, ["statistics", "method"], nil),
            &Map.put(&1, "unexpected", 1)
          ] do
        invalid = update.(stored)

        assert :error =
                 AnalysisContract.decode_output(%{
                   "family_result" => %{"comparisons" => [invalid]}
                 })
      end
    end

    test "the encoder rejects a family that it cannot store" do
      assert :error = AnalysisContract.encode_output(%Output{family_result: nil})
      assert :error = AnalysisContract.encode_output(%Output{family_result: family([])})
      assert :error = AnalysisContract.encode_output(:invalid)

      assert :error =
               AnalysisContract.encode_output(%Output{
                 family_result: family([%{comparison(0) | statistics: unknown_method()}])
               })

      assert :error =
               AnalysisContract.encode_output(%Output{
                 family_result: family([%{comparison(0) | adjustment: %Adjustment{}}])
               })
    end
  end

  describe "statistics transport" do
    test "one statistics value round trips through the mapped task result" do
      value = statistics(1)

      assert {:ok, params} = AnalysisContract.encode_statistics(value)
      assert {:ok, ^value} = AnalysisContract.decode_statistics(params)
      assert params["estimate"]["contrast"] == "alternative_minus_reference"
    end

    test "the statistics codec rejects a value outside the declared shape" do
      {:ok, params} = AnalysisContract.encode_statistics(statistics(0))

      for update <- [
            &Map.delete(&1, "assessment"),
            &Map.put(&1, "estimate", %{"contrast" => "alternative_minus_reference"}),
            &Map.put(&1, "interval", %{"confidence_level" => 0.95, "lower" => 0.1}),
            &Map.put(&1, "method", :matching_bounded_mean_v1),
            &Map.put(&1, "test", %{"method" => "sign_conservative_betting"})
          ] do
        assert :error = AnalysisContract.decode_statistics(update.(params))
      end

      assert :error = AnalysisContract.decode_statistics(:invalid)
    end

    test "the encoder rejects statistics without a closed scientific literal" do
      assert :error = AnalysisContract.encode_statistics(unknown_method())

      assert :error =
               AnalysisContract.encode_statistics(%{
                 statistics(0)
                 | estimate: %Estimate{contrast: :alternative_minus_reference, value: :nan}
               })
    end
  end

  defp family(comparisons), do: %CorrectedFamily{comparisons: comparisons}

  defp family_params(%{"family_result" => family}), do: family

  # One corrected comparison of the declared family. The values illustrate the
  # transport shape; the scientific content belongs to the analysis capability.
  defp comparison(position) do
    %CorrectedFamily.Comparison{
      statistics: statistics(position),
      adjustment: %Adjustment{
        adjusted_p_value: 0.06 + position / 100,
        reject_null: position == 1
      }
    }
  end

  defp statistics(position) do
    %Statistics{
      method: :matching_bounded_mean_v1,
      estimate: %Estimate{contrast: :alternative_minus_reference, value: 0.2 + position},
      interval: %Interval{
        confidence_level: 0.95,
        lower: 0.05 + position,
        upper: 0.4 + position
      },
      test: %Test{
        method: :sign_conservative_betting,
        alternative: :two_sided,
        raw_p_value: 0.04 + position / 100
      },
      assessment: %Assessment{status: :informative, warnings: []}
    }
  end

  defp unknown_method do
    %{statistics(0) | method: :unknown_method}
  end
end
