defmodule NetworkDefense.Evaluation2.Study.Views do
  @moduledoc false

  # Construction of the supported study values from internal records. These
  # functions read no stored row and create no persistence record.
  #
  # The declared comparison tier is a definition string, so any tier outside the
  # closed order returns the bounded corruption error. The result view joins stored
  # corrected outputs to declared identities by declared position.
  #
  # `error/1` is the only public normalization of one internal persistence failure.

  alias NetworkDefense.DefenseActions.Registry, as: Actions
  alias NetworkDefense.Evaluation2.Study.AuthoredDefinition
  alias NetworkDefense.Evaluation2.Study.Comparison
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.DefinitionOptions
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.ExecutionSummary
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Page
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Browsing
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result, as: ResultView
  alias NetworkDefense.Evaluation2.Study.Result.Comparison, as: ResultComparison
  alias NetworkDefense.Evaluation2.Study.Result.Family, as: ResultFamily
  alias NetworkDefense.Evaluation2.Study.Revision, as: RevisionView
  alias NetworkDefense.Evaluation2.Study.RevisionContext
  alias NetworkDefense.Evaluation2.Study.RevisionDetail
  alias NetworkDefense.Evaluation2.Study.RevisionSummary
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.Study.StrategyOption
  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.Rules.Registry, as: Rules

  @typedoc "One supported result view or its bounded failure."
  @type result_response :: {:ok, ResultView.t()} | {:error, Error.t()}

  @spec revision(%{
          required(:study_id) => String.t(),
          required(:revision) => pos_integer(),
          optional(atom()) => term()
        }) :: RevisionView.t()
  def revision(%{study_id: study_id, revision: revision}) do
    %RevisionView{study_id: study_id, revision: revision}
  end

  @spec revision_detail(Persistence.Revision.t()) :: RevisionDetail.t()
  def revision_detail(%Persistence.Revision{definition: definition} = stored) do
    %RevisionDetail{
      revision: revision(stored),
      authored: AuthoredDefinition.new(definition),
      context: %RevisionContext{
        method: definition.provenance.method,
        seed_contract: definition.provenance.seed_contract,
        measurement_label: definition.provenance.environment_label
      },
      structure: Definition.structure(definition)
    }
  end

  @spec revision_summary(Browsing.revision_entry()) :: RevisionSummary.t()
  def revision_summary(entry) do
    %RevisionSummary{
      revision: revision(entry),
      created_at: entry.inserted_at,
      execution_count: entry.execution_count,
      latest_state: entry.latest_state
    }
  end

  @spec execution_summary(
          %{study_id: String.t(), revision: pos_integer()},
          Browsing.execution_entry()
        ) ::
          ExecutionSummary.t()
  def execution_summary(identity, entry) do
    %ExecutionSummary{
      execution_id: entry.id,
      revision: revision(identity),
      state: entry.state,
      pilot_outcome: entry.pilot_outcome,
      selection: entry.selection,
      started_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  @spec page(
          %{
            entries: [stored_entry],
            page: pos_integer(),
            page_size: pos_integer(),
            total: non_neg_integer()
          },
          (stored_entry -> Page.entry())
        ) :: Page.t()
        when stored_entry: term()
  def page(stored, map_entry) do
    %Page{
      entries: Enum.map(stored.entries, map_entry),
      page: stored.page,
      page_size: stored.page_size,
      total: stored.total
    }
  end

  @spec definition_options() :: DefinitionOptions.t()
  def definition_options do
    %DefinitionOptions{
      actions: Enum.map(Actions.values(), &Atom.to_string/1),
      rules: Enum.map(Rules.values(), &Atom.to_string/1),
      alternatives: Enum.map(Definition.alternative_strategies(), &strategy_option/1),
      objectives: Enum.map(SimulationObjective.values(), &Atom.to_string/1),
      measurement_label: Definition.measurement_label()
    }
  end

  defp strategy_option(strategy) do
    %StrategyOption{
      value: Atom.to_string(strategy),
      scoring_required: OptimizationParams.requires_simulation_params?(strategy),
      action_types: Enum.map(Definition.supported_action_types(strategy), &Atom.to_string/1)
    }
  end

  @spec status(Persistence.Revision.t(), Persistence.Execution.t()) :: Status.t()
  def status(revision, execution) do
    %Status{
      execution_id: execution.id,
      revision: revision(revision),
      state: execution.state,
      pilot_outcome: execution.pilot_outcome,
      selection: execution.selection,
      error: execution.error
    }
  end

  @spec pilot_result(Persistence.Revision.t(), AnalysisContract.Output.t()) ::
          {:ok, PilotResult.t()} | {:error, Error.t()}
  def pilot_result(revision, output) do
    with {:ok, identities} <- comparison_identities(Definition.comparisons(revision.definition)),
         :ok <- pilot_positions(output, length(identities)) do
      candidates = Enum.map(output.candidates, &pilot_candidate(&1, identities))

      {:ok,
       %PilotResult{
         method: :precision_pilot_v1,
         selection_rule: :lowest_predicted_runtime,
         outcome: output.outcome,
         candidates: candidates
       }}
    end
  end

  defp pilot_positions(output, count) do
    positions = Enum.to_list(0..(count - 1))

    valid? =
      Enum.all?(output.candidates, fn candidate ->
        Enum.map(candidate.comparisons, & &1.comparison_position) == positions
      end)

    if valid?, do: :ok, else: {:error, corrupt_storage_error()}
  end

  defp pilot_candidate(candidate, identities) do
    comparisons =
      Enum.map(candidate.comparisons, fn assessment ->
        %PilotResult.Comparison{
          identity: Enum.fetch!(identities, assessment.comparison_position),
          guarded_half_width: assessment.guarded_half_width,
          informative: assessment.informative,
          passes: assessment.passes
        }
      end)

    %PilotResult.Candidate{
      id: candidate.candidate_id,
      plan_count_per_side: candidate.plan_count_per_side,
      attacks_per_plan: candidate.attacks_per_plan,
      predicted_runtime_ms: candidate.predicted_runtime_ms,
      comparisons: comparisons
    }
  end

  # Join the accepted execution facts with the stored Final outputs. A value that
  # lacks one of them is not a result.
  @spec result(Persistence.Revision.t(), Persistence.Execution.t(), Persistence.Result.t()) ::
          result_response()
  def result(revision, execution, stored_result) do
    with {:ok, pilot_outcome} <- accepted_outcome(execution),
         {:ok, selection} <- accepted_selection(execution),
         {:ok, family} <- family(revision.definition, stored_result.family) do
      {:ok,
       %ResultView{
         execution_id: execution.id,
         revision: revision(revision),
         pilot_outcome: pilot_outcome,
         selection: selection,
         family: family,
         timing: stored_result.timing
       }}
    end
  end

  # A non-successful execution owns no result, so the facade reports this bounded
  # failure instead of an internal persistence error.
  @spec result_unavailable() :: Error.t()
  def result_unavailable do
    %Error{
      category: :validation_failed,
      issues: [
        %Error.Issue{
          code: "result_not_available",
          path: [],
          message: "The study execution has not succeeded."
        }
      ]
    }
  end

  # A stored definition is application data, so only the three declared tier
  # strings convert.
  @spec comparison(Definition.comparison()) ::
          {:ok, Comparison.t()} | {:error, Error.t()}
  def comparison(%{
        tier: tier,
        budget: budget,
        alternative: alternative,
        reference: reference,
        outcome: outcome
      }) do
    case stored_tier(tier) do
      {:ok, tier} ->
        {:ok,
         %Comparison{
           tier: tier,
           budget: budget,
           alternative: alternative,
           reference: reference,
           outcome: outcome
         }}

      :error ->
        {:error, corrupt_storage_error()}
    end
  end

  defp stored_tier("small"), do: {:ok, :small}
  defp stored_tier("medium"), do: {:ok, :medium}
  defp stored_tier("large"), do: {:ok, :large}
  defp stored_tier(_tier), do: :error

  @spec error(Persistence.Error.t()) :: Error.t()
  def error(%Persistence.Error{} = failure) do
    {category, code, message} = public_failure(failure)

    %Error{
      category: category,
      issues: [%Error.Issue{code: code, path: [], message: message}]
    }
  end

  # The Family size is the declared comparison count, and each stored value keeps
  # its declared position.
  @spec family(Definition.t(), CorrectedFamily.t()) ::
          {:ok, ResultFamily.t()} | {:error, Error.t()}
  defp family(%Definition{} = definition, %CorrectedFamily{comparisons: stored}) do
    declared = Definition.comparisons(definition)
    declared_family = definition.family

    with :ok <- same_comparison_count(declared, stored),
         {:ok, identities} <- comparison_identities(declared) do
      comparisons =
        identities
        |> Enum.zip(stored)
        |> Enum.map(fn {identity, stored_comparison} ->
          %ResultComparison{
            identity: identity,
            statistics: stored_comparison.statistics,
            adjustment: stored_comparison.adjustment
          }
        end)

      {:ok,
       %ResultFamily{
         id: declared_family.id,
         method: :holm,
         alpha: declared_family.alpha,
         comparisons: comparisons
       }}
    end
  end

  defp comparison_identities(declared) do
    declared
    |> Enum.reduce_while({:ok, []}, fn declared_comparison, {:ok, identities} ->
      case comparison(declared_comparison) do
        {:ok, identity} -> {:cont, {:ok, [identity | identities]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, identities} -> {:ok, Enum.reverse(identities)}
      {:error, _} = error -> error
    end
  end

  defp same_comparison_count(declared, stored) do
    if length(declared) == length(stored) do
      :ok
    else
      {:error, corrupt_storage_error()}
    end
  end

  defp accepted_outcome(%Persistence.Execution{pilot_outcome: %PilotOutcome{} = outcome}),
    do: {:ok, outcome}

  defp accepted_outcome(%Persistence.Execution{}), do: {:error, corrupt_storage_error()}

  defp accepted_selection(%Persistence.Execution{selection: %Selection{} = selection}),
    do: {:ok, selection}

  defp accepted_selection(%Persistence.Execution{}), do: {:error, corrupt_storage_error()}

  defp corrupt_storage_error do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "corrupt_storage",
          path: [],
          message: "The stored study data cannot be read."
        }
      ]
    }
  end

  # Fixed public wording per failure kind. The internal operation, resource, and
  # cause never reach the caller.
  @spec public_failure(Persistence.Error.t()) ::
          {Error.category(), String.t(), String.t()}
  defp public_failure(%Persistence.Error{kind: :not_found, resource: :revision}) do
    {:validation_failed, "revision_not_found", "The declared study revision does not exist."}
  end

  defp public_failure(%Persistence.Error{kind: :not_found, resource: :execution}) do
    {:validation_failed, "execution_not_found", "The study execution does not exist."}
  end

  defp public_failure(%Persistence.Error{kind: :not_found, resource: :result}) do
    {:validation_failed, "result_not_found", "The study execution has no stored result."}
  end

  defp public_failure(%Persistence.Error{kind: :not_found}) do
    {:unavailable, "record_not_found", "The stored study record does not exist."}
  end

  defp public_failure(%Persistence.Error{kind: :conflict, resource: :approval}) do
    {:validation_failed, "invalid_approval",
     "The approval does not match the accepted Pilot outcome."}
  end

  defp public_failure(%Persistence.Error{kind: :conflict}) do
    {:conflict, "conflict", "The study request conflicts with the stored state."}
  end

  defp public_failure(%Persistence.Error{kind: :storage}) do
    {:unavailable, "storage_unavailable", "The study storage is unavailable."}
  end

  defp public_failure(%Persistence.Error{kind: :corrupt_data}) do
    {:unavailable, "corrupt_storage", "The stored study data cannot be read."}
  end
end
