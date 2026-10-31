defmodule NetworkDefense.Evaluation2.Study.Final.AnalysisContract do
  @moduledoc """
  Transport contract of one Final analysis Gust run.

  The root input names the analysis phase run and the accepted Final snapshot.
  The terminal output holds the corrected comparison family of the declared
  family. The comparison list keeps the declared family order, so one stored
  position belongs to one declared comparison.

  A stored run input and a stored terminal result cross the Gust JSON boundary,
  so both codecs are strict:

    * the run input carries the canonical phase-run UUID under
      `"study_phase_run_id"` and the canonical snapshot UUID under
      `"study_evidence_snapshot_id"`;
    * the terminal output carries the corrected family under `"family_result"`.

  ```json
  {
    "study_phase_run_id": "<canonical UUID>",
    "study_evidence_snapshot_id": "<canonical UUID>"
  }
  ```

  ```json
  {
    "family_result": {
      "comparisons": [
        {
          "statistics": {
            "method": "matching_bounded_mean_v1",
            "estimate": {"contrast": "alternative_minus_reference", "value": 0.25},
            "interval": {"confidence_level": 0.95, "lower": 0.1, "upper": 0.4},
            "test": {
              "method": "sign_conservative_betting",
              "alternative": "two_sided",
              "raw_p_value": 0.03
            },
            "assessment": {"status": "informative", "warnings": []}
          },
          "adjustment": {"adjusted_p_value": 0.06, "reject_null": false}
        }
      ]
    }
  }
  ```

  The nested values use closed literals, because a stored result must name
  exactly one scientific method. One unusable comparison rejects the whole
  family, so a partial family never becomes a stored result.

  The mapped evaluation task stores one statistics value of this module. Both
  directions of that transport use the shared `encode_statistics/1` and
  `decode_statistics/1` codec, so the mapped result and the terminal family keep
  one stored statistics shape.
  """

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

  @typedoc "One JSON-safe Gust parameter object."
  @type params :: %{required(String.t()) => term()}

  # Sorted key sets make the stored shape canonical in both directions.
  @input_keys ["study_evidence_snapshot_id", "study_phase_run_id"]
  @output_keys ["family_result"]
  @family_keys ["comparisons"]
  @comparison_keys ["adjustment", "statistics"]
  @statistics_keys ["assessment", "estimate", "interval", "method", "test"]
  @estimate_keys ["contrast", "value"]
  @interval_keys ["confidence_level", "lower", "upper"]
  @test_keys ["alternative", "method", "raw_p_value"]
  @assessment_keys ["status", "warnings"]
  @adjustment_keys ["adjusted_p_value", "reject_null"]

  # Closed literal sets keep one stored spelling per scientific value.
  @methods [matching_bounded_mean_v1: "matching_bounded_mean_v1"]
  @contrasts [alternative_minus_reference: "alternative_minus_reference"]
  @test_methods [sign_conservative_betting: "sign_conservative_betting"]
  @alternatives [two_sided: "two_sided"]
  @statuses [informative: "informative", non_informative: "non_informative"]
  @warnings [empty_inversion: "empty_inversion"]

  @doc """
  Encode the root input of one Final analysis run as JSON-safe run parameters.
  """
  @spec to_params(Input.t()) :: params()
  def to_params(%Input{phase_run_id: phase_run_id, snapshot_id: snapshot_id}) do
    %{
      "study_phase_run_id" => phase_run_id,
      "study_evidence_snapshot_id" => snapshot_id
    }
  end

  @doc """
  Decode the stored input of one Final analysis run.

  Only the canonical lower-case UUID form is accepted, so a decoded input names
  exactly one stored phase run and one stored snapshot.
  """
  @spec decode_input(map()) :: {:ok, Input.t()} | :error
  def decode_input(
        %{
          "study_phase_run_id" => phase_run_id,
          "study_evidence_snapshot_id" => snapshot_id
        } = params
      ) do
    with true <- exact_keys?(params, @input_keys),
         true <- canonical_uuid?(phase_run_id),
         true <- canonical_uuid?(snapshot_id) do
      {:ok, %Input{phase_run_id: phase_run_id, snapshot_id: snapshot_id}}
    else
      _rejected -> :error
    end
  end

  def decode_input(_params), do: :error

  @doc """
  Encode the terminal output of one Final analysis run as a JSON-safe result.

  The caller that stores the run result owns this step, so the terminal task and
  the completion acceptance keep one stored shape.
  """
  @spec encode_output(Output.t()) :: {:ok, params()} | :error
  def encode_output(%Output{family_result: family}) do
    with {:ok, comparisons} <- encode_family(family) do
      {:ok, %{"family_result" => %{"comparisons" => comparisons}}}
    end
  end

  def encode_output(_output), do: :error

  @doc """
  Decode the stored terminal result of one Final analysis run.

  The complete corrected family stays in this value, because the acceptance
  transaction stores it as the result record.
  """
  @spec decode_output(map()) :: {:ok, Output.t()} | :error
  def decode_output(%{"family_result" => family} = params) do
    with true <- exact_keys?(params, @output_keys),
         {:ok, comparisons} <- decode_family(family) do
      {:ok, %Output{family_result: %CorrectedFamily{comparisons: comparisons}}}
    else
      _rejected -> :error
    end
  end

  def decode_output(_params), do: :error

  @doc false
  @spec decode_output!(map()) :: Output.t()
  def decode_output!(params) do
    {:ok, output} = decode_output(params)
    output
  end

  # --- corrected family --------------------------------------------------

  # A correctable family has at least one declared comparison.
  defp encode_family(%CorrectedFamily{comparisons: [_declared | _rest] = comparisons}) do
    collect(Enum.map(comparisons, &encode_comparison/1))
  end

  defp encode_family(_family), do: :error

  defp decode_family(%{"comparisons" => [_declared | _rest] = entries} = params) do
    with true <- exact_keys?(params, @family_keys) do
      collect(Enum.map(entries, &decode_comparison/1))
    end
  end

  defp decode_family(_family), do: :error

  defp encode_comparison(%CorrectedFamily.Comparison{
         statistics: statistics,
         adjustment: adjustment
       }) do
    with {:ok, statistics} <- encode_statistics(statistics),
         {:ok, adjustment} <- encode_adjustment(adjustment) do
      {:ok, %{"statistics" => statistics, "adjustment" => adjustment}}
    end
  end

  defp encode_comparison(_comparison), do: :error

  defp decode_comparison(%{"statistics" => statistics, "adjustment" => adjustment} = params) do
    with true <- exact_keys?(params, @comparison_keys),
         {:ok, statistics} <- decode_statistics(statistics),
         {:ok, adjustment} <- decode_adjustment(adjustment) do
      {:ok, %CorrectedFamily.Comparison{statistics: statistics, adjustment: adjustment}}
    else
      _rejected -> :error
    end
  end

  defp decode_comparison(_comparison), do: :error

  # --- statistics --------------------------------------------------------

  @doc """
  Encode one comparison statistics value as JSON-safe task parameters.
  """
  @spec encode_statistics(Statistics.t()) :: {:ok, params()} | :error
  def encode_statistics(%Statistics{
        method: method,
        estimate: estimate,
        interval: interval,
        test: test,
        assessment: assessment
      }) do
    with {:ok, method} <- literal_encode(method, @methods),
         {:ok, estimate} <- encode_estimate(estimate),
         {:ok, interval} <- encode_interval(interval),
         {:ok, test} <- encode_test(test),
         {:ok, assessment} <- encode_assessment(assessment) do
      {:ok,
       %{
         "method" => method,
         "estimate" => estimate,
         "interval" => interval,
         "test" => test,
         "assessment" => assessment
       }}
    end
  end

  def encode_statistics(_statistics), do: :error

  @doc """
  Decode one stored comparison statistics value.
  """
  @spec decode_statistics(map()) :: {:ok, Statistics.t()} | :error
  def decode_statistics(
        %{
          "method" => method,
          "estimate" => estimate,
          "interval" => interval,
          "test" => test,
          "assessment" => assessment
        } = params
      ) do
    with true <- exact_keys?(params, @statistics_keys),
         {:ok, method} <- literal_decode(method, @methods),
         {:ok, estimate} <- decode_estimate(estimate),
         {:ok, interval} <- decode_interval(interval),
         {:ok, test} <- decode_test(test),
         {:ok, assessment} <- decode_assessment(assessment) do
      {:ok,
       %Statistics{
         method: method,
         estimate: estimate,
         interval: interval,
         test: test,
         assessment: assessment
       }}
    else
      _rejected -> :error
    end
  end

  def decode_statistics(_params), do: :error

  defp encode_estimate(%Estimate{contrast: contrast, value: value}) do
    with {:ok, contrast} <- literal_encode(contrast, @contrasts),
         {:ok, value} <- number(value) do
      {:ok, %{"contrast" => contrast, "value" => value}}
    end
  end

  defp encode_estimate(_estimate), do: :error

  defp decode_estimate(%{"contrast" => contrast, "value" => value} = params) do
    with true <- exact_keys?(params, @estimate_keys),
         {:ok, contrast} <- literal_decode(contrast, @contrasts),
         {:ok, value} <- number(value) do
      {:ok, %Estimate{contrast: contrast, value: value}}
    else
      _rejected -> :error
    end
  end

  defp decode_estimate(_estimate), do: :error

  # A confidence interval needs an ordered interval inside the open unit range.
  defp encode_interval(%Interval{confidence_level: level, lower: lower, upper: upper}) do
    with {:ok, level} <- number(level),
         {:ok, lower} <- number(lower),
         {:ok, upper} <- number(upper),
         true <- level > 0.0 and level < 1.0 and lower <= upper do
      {:ok, %{"confidence_level" => level, "lower" => lower, "upper" => upper}}
    else
      _rejected -> :error
    end
  end

  defp encode_interval(_interval), do: :error

  defp decode_interval(
         %{"confidence_level" => level, "lower" => lower, "upper" => upper} = params
       ) do
    with true <- exact_keys?(params, @interval_keys),
         {:ok, level} <- number(level),
         {:ok, lower} <- number(lower),
         {:ok, upper} <- number(upper),
         true <- level > 0.0 and level < 1.0 and lower <= upper do
      {:ok, %Interval{confidence_level: level, lower: lower, upper: upper}}
    else
      _rejected -> :error
    end
  end

  defp decode_interval(_interval), do: :error

  defp encode_test(%Test{method: method, alternative: alternative, raw_p_value: raw_p_value}) do
    with {:ok, method} <- literal_encode(method, @test_methods),
         {:ok, alternative} <- literal_encode(alternative, @alternatives),
         {:ok, raw_p_value} <- probability(raw_p_value) do
      {:ok,
       %{
         "method" => method,
         "alternative" => alternative,
         "raw_p_value" => raw_p_value
       }}
    end
  end

  defp encode_test(_test), do: :error

  defp decode_test(
         %{"method" => method, "alternative" => alternative, "raw_p_value" => raw_p_value} =
           params
       ) do
    with true <- exact_keys?(params, @test_keys),
         {:ok, method} <- literal_decode(method, @test_methods),
         {:ok, alternative} <- literal_decode(alternative, @alternatives),
         {:ok, raw_p_value} <- probability(raw_p_value) do
      {:ok, %Test{method: method, alternative: alternative, raw_p_value: raw_p_value}}
    else
      _rejected -> :error
    end
  end

  defp decode_test(_test), do: :error

  defp encode_assessment(%Assessment{status: status, warnings: warnings}) do
    with {:ok, status} <- literal_encode(status, @statuses),
         {:ok, warnings} <- encode_warnings(warnings) do
      {:ok, %{"status" => status, "warnings" => warnings}}
    end
  end

  defp encode_assessment(_assessment), do: :error

  defp decode_assessment(%{"status" => status, "warnings" => warnings} = params) do
    with true <- exact_keys?(params, @assessment_keys),
         {:ok, status} <- literal_decode(status, @statuses),
         {:ok, warnings} <- decode_warnings(warnings) do
      {:ok, %Assessment{status: status, warnings: warnings}}
    else
      _rejected -> :error
    end
  end

  defp decode_assessment(_assessment), do: :error

  defp encode_warnings(warnings) when is_list(warnings) do
    collect(Enum.map(warnings, &literal_encode(&1, @warnings)))
  end

  defp encode_warnings(_warnings), do: :error

  defp decode_warnings(warnings) when is_list(warnings) do
    collect(Enum.map(warnings, &literal_decode(&1, @warnings)))
  end

  defp decode_warnings(_warnings), do: :error

  # --- family adjustment -------------------------------------------------

  defp encode_adjustment(%Adjustment{
         adjusted_p_value: adjusted_p_value,
         reject_null: reject_null
       })
       when is_boolean(reject_null) do
    with {:ok, adjusted_p_value} <- probability(adjusted_p_value) do
      {:ok, %{"adjusted_p_value" => adjusted_p_value, "reject_null" => reject_null}}
    end
  end

  defp encode_adjustment(_adjustment), do: :error

  defp decode_adjustment(
         %{"adjusted_p_value" => adjusted_p_value, "reject_null" => reject_null} = params
       )
       when is_boolean(reject_null) do
    with true <- exact_keys?(params, @adjustment_keys),
         {:ok, adjusted_p_value} <- probability(adjusted_p_value) do
      {:ok, %Adjustment{adjusted_p_value: adjusted_p_value, reject_null: reject_null}}
    else
      _rejected -> :error
    end
  end

  defp decode_adjustment(_adjustment), do: :error

  # --- shared helpers ----------------------------------------------------

  # A JSON number keeps integral values as integers, so every decoded number is
  # normalized to the declared float type.
  defp number(value) when is_number(value), do: {:ok, value * 1.0}

  defp number(_value), do: :error

  defp probability(value) do
    with {:ok, value} <- number(value) do
      if value >= 0.0 and value <= 1.0, do: {:ok, value}, else: :error
    end
  end

  defp literal_encode(value, table) when is_atom(value) do
    if Keyword.has_key?(table, value), do: {:ok, Atom.to_string(value)}, else: :error
  end

  defp literal_encode(_value, _table), do: :error

  defp literal_decode(value, table) when is_binary(value) do
    case Enum.find(table, fn {_literal, encoded} -> encoded == value end) do
      {literal, _encoded} -> {:ok, literal}
      nil -> :error
    end
  end

  defp literal_decode(_value, _table), do: :error

  defp exact_keys?(params, expected_keys), do: Enum.sort(Map.keys(params)) == expected_keys

  # One unusable entry rejects the whole stored value, so a partial family never
  # reaches acceptance or reporting.
  @spec collect([{:ok, value} | :error]) :: {:ok, [value]} | :error when value: var
  defp collect([]), do: {:ok, []}

  defp collect([{:ok, value} | rest]) do
    case collect(rest) do
      {:ok, values} -> {:ok, [value | values]}
      :error -> :error
    end
  end

  defp collect([_error | _rest]), do: :error

  # Only the canonical lower-case form names one stored record.
  @spec canonical_uuid?(term()) :: boolean()
  defp canonical_uuid?(value) when is_binary(value), do: Ecto.UUID.cast(value) == {:ok, value}
  defp canonical_uuid?(_value), do: false
end
