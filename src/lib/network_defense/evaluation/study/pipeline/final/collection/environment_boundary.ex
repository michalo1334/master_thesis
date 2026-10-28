defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.EnvironmentBoundary do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.Environment

  # One tier boundary of the measured environment.
  #
  # The deployed revision can change while a run is in flight, so every boundary
  # reads the configured value again. The declared value comes from the stored
  # definition that the loader already validated.
  @spec run(IO.Tier.t()) :: {:ok, IO.Tier.t()} | {:error, StudyError.t()}
  def run(%IO.Tier{definition: definition} = tier) do
    case Environment.matches(definition.study.revisions.environment, configured_revision()) do
      :ok -> {:ok, tier}
      {:error, :missing_environment} -> {:error, StudyError.measured_environment_unavailable()}
      {:error, :environment_mismatch} -> {:error, StudyError.measured_environment_changed()}
    end
  end

  defp configured_revision do
    Application.get_env(:network_defense, :measured_environment_revision)
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.EnvironmentBoundary

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_tier_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO.Tier{phase_run: phase_run}), do: %{"study_phase_run_id" => phase_run.id}
  end
end
