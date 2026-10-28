defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.CompleteTier do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO

  # Completion of one tier run.
  #
  # The loader already checked the run parameters against the stored phase run
  # and phase, so this step hands the validated identity back as the receipt.
  # The workflow compares that receipt with the run parameters.
  @spec run(IO.Tier.t()) :: {:ok, IO.Tier.t()} | {:error, StudyError.t()}
  def run(%IO.Tier{tier: tier, tier_position: position} = io)
      when is_binary(tier) and byte_size(tier) > 0 and is_integer(position) and position >= 0 do
    {:ok, io}
  end

  def run(%IO.Tier{}), do: {:error, StudyError.final_timing_invalid()}

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.CompleteTier

    alias NetworkDefense.Evaluation.Study.Contracts.StudyError
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}) do
      # Every identity fault of this task is one bounded Final timing error.
      case IO.load_tier_from_gust_run(run_id) do
        {:ok, tier} -> {:ok, tier}
        {:error, _error} -> {:error, StudyError.final_timing_invalid()}
      end
    end

    @impl GustAdapter
    def encode(%IO.Tier{tier: tier, tier_position: position, phase_run: phase_run}) do
      %{
        "study_phase_run_id" => phase_run.id,
        "tier" => tier,
        "tier_position" => position
      }
    end
  end
end
