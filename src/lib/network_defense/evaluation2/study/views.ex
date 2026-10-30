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

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Comparison
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result, as: ResultView
  alias NetworkDefense.Evaluation2.Study.Result.Comparison, as: ResultComparison
  alias NetworkDefense.Evaluation2.Study.Result.Family, as: ResultFamily
  alias NetworkDefense.Evaluation2.Study.Revision, as: RevisionView
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Status

  @typedoc "One supported result view or its bounded failure."
  @type result_response :: {:ok, ResultView.t()} | {:error, Error.t()}

  @spec revision(Persistence.Revision.t()) :: RevisionView.t()
  def revision(%Persistence.Revision{study_id: study_id, revision: revision}) do
    %RevisionView{study_id: study_id, revision: revision}
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
          PilotResult.t()
  def pilot_result(_revision, _output),
    do: raise(NotImplementedError, function: :pilot_result)

  # Join the accepted execution facts with the stored Final outputs. A value that
  # lacks one of them is not a result.
  @spec result(Persistence.Revision.t(), Persistence.Execution.t(), Persistence.Result.t()) ::
          result_response()
  def result(revision, execution, stored_result) do
    with {:ok, pilot_outcome} <- accepted_outcome(execution),
         {:ok, selection} <- accepted_selection(execution),
         {:ok, family} <- family(revision.definition.family, stored_result.family) do
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
  @spec family(Definition.family(), CorrectedFamily.t()) ::
          {:ok, ResultFamily.t()} | {:error, Error.t()}
  defp family(%{comparisons: declared} = declared_family, %CorrectedFamily{comparisons: stored}) do
    with :ok <- same_comparison_count(declared, stored),
         {:ok, method} <- family_method(declared_family.method),
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
         method: method,
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

  # The creation contract validates the correction method, so one accepted literal
  # exists.
  defp family_method("holm"), do: {:ok, :holm}
  defp family_method(_method), do: {:error, corrupt_storage_error()}

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
