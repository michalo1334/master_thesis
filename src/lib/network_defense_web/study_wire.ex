defmodule NetworkDefenseWeb.StudyWire do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Contracts
  alias NetworkDefense.Evaluation2.Study.PilotResult.Candidate
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefenseWeb.Contracts.Dashboard.Study.Reply

  def reply({:error, error}), do: %{status: "error", error: wire(error)}

  def wire(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def wire(%_{} = value), do: value |> Map.from_struct() |> wire()

  def wire(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, wire(value)} end)

  def wire(value) when is_list(value), do: Enum.map(value, &wire/1)
  def wire(value), do: Contracts.to_wire(value)

  def error(code, message) do
    %{
      status: "error",
      error: %{category: "validation_failed", issues: [%{code: code, path: [], message: message}]}
    }
  end

  def validation_error(%Changeset{} = changeset) do
    %{
      status: "error",
      error: %{
        category: "validation_failed",
        issues: changeset_issues(changeset, []) |> Enum.take(50)
      }
    }
  end

  defp changeset_issues(changeset, path) do
    own =
      Enum.flat_map(changeset.errors, fn {field, {_message, metadata}} ->
        Enum.map(field_paths(changeset, field, metadata, path), fn field_path ->
          %{code: "invalid_field", path: field_path, message: "Supply a valid value."}
        end)
      end)

    nested =
      Enum.flat_map(changeset.changes, fn {field, value} ->
        nested_issues(value, path ++ [to_string(field)])
      end)

    own ++ nested
  end

  defp field_paths(changeset, field, metadata, path) do
    base = path ++ [to_string(field)]

    case {metadata[:type], (changeset.params || %{})[to_string(field)]} do
      {{:array, type}, values} when is_list(values) ->
        invalid =
          values
          |> Enum.with_index()
          |> Enum.reject(fn {value, _index} -> match?({:ok, _}, Ecto.Type.cast(type, value)) end)
          |> Enum.map(fn {_value, index} -> base ++ [index] end)

        if invalid == [], do: [base], else: invalid

      _ ->
        [base]
    end
  end

  defp nested_issues(%Changeset{} = changeset, path), do: changeset_issues(changeset, path)

  defp nested_issues(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> nested_issues(value, path ++ [index]) end)
  end

  defp nested_issues(_value, _path), do: []

  def definition_params(definition) do
    %{
      study: %{id: definition.study_id, revision: definition.revision},
      seed: definition.seed,
      family: %{id: definition.family_id, alpha: definition.family_alpha},
      analysis: %{confidence_level: definition.confidence_level},
      defense: Map.take(definition, [:feasibility, :allowed_action_types]),
      simulation: Map.take(definition, [:iterations_per_run, :max_attempts, :rules]),
      tiers:
        Map.new(definition.tiers, fn tier ->
          alternatives =
            Enum.map(tier.alternatives, fn alternative ->
              base = %{strategy: alternative.strategy}

              if is_nil(alternative.objective),
                do: base,
                else:
                  Map.put(
                    base,
                    :scoring,
                    Map.take(alternative, [:objective, :monte_carlo_trials])
                  )
            end)

          {tier.tier,
           tier
           |> Map.take([:graph_revision_id, :foothold_node_id, :budgets])
           |> Map.put(:alternatives, alternatives)}
        end),
      pilot: %{
        candidates: definition.candidates,
        extra_pool: %{plans: definition.extra_pool_plans, attacks: definition.extra_pool_attacks},
        precision: Map.take(definition, [:outer_subsamples, :target_half_width, :guard_quantile])
      }
    }
    |> Contracts.to_params()
  end

  def pilot(value) do
    result = wire(value)

    Map.put(
      result,
      :candidates,
      Enum.map(value.candidates, fn candidate ->
        candidate
        |> wire()
        |> Map.merge(%{
          worst_guarded_half_width: Candidate.worst_guarded_half_width(candidate),
          passes: Candidate.passes?(candidate)
        })
      end)
    )
  end

  def result(value) do
    %{
      execution_id: value.execution_id,
      revision: wire(value.revision),
      pilot_outcome: wire(value.pilot_outcome),
      selection: wire(value.selection),
      family_id: value.family.id,
      family_method: to_string(value.family.method),
      family_alpha: value.family.alpha,
      comparisons: Enum.map(value.family.comparisons, &comparison/1),
      timing: Enum.map(Tier.all(), &timing(value.timing, &1))
    }
  end

  defp comparison(value) do
    s = value.statistics

    %{
      identity: wire(value.identity),
      method: to_string(s.method),
      contrast: to_string(s.estimate.contrast),
      estimate: s.estimate.value,
      confidence_level: s.interval.confidence_level,
      lower: s.interval.lower,
      upper: s.interval.upper,
      test_method: to_string(s.test.method),
      test_alternative: to_string(s.test.alternative),
      raw_p_value: s.test.raw_p_value,
      adjusted_p_value: value.adjustment.adjusted_p_value,
      reject_null: value.adjustment.reject_null,
      assessment: to_string(s.assessment.status),
      warnings: Enum.map(s.assessment.warnings, &to_string/1)
    }
  end

  defp timing(timing, tier) do
    %{
      tier: to_string(tier),
      replicas:
        Enum.map(0..4, fn position ->
          timing.by_tier[tier].replicas[position] |> wire() |> Map.put(:position, position)
        end),
      summaries:
        Enum.map([:plan_selection, :simulation, :total], fn boundary ->
          {minimum, maximum} = Timing.range(timing, tier, boundary)

          %{
            boundary: to_string(boundary),
            median_us: Timing.median(timing, tier, boundary),
            minimum_us: minimum,
            maximum_us: maximum
          }
        end)
    }
  end

  @doc false
  def validate_reply(reply) do
    case Reply.validate(reply) do
      {:ok, value} -> Reply.to_wire(value)
      {:error, _changeset} -> error("invalid_reply", "The study reply could not be represented.")
    end
  end
end
