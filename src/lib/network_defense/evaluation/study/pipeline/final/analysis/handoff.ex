defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Handoff do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Handoff.Run
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.TimingSummary

  # Persisted Final Collection to Final Analysis handoff.
  #
  # The locked `final_collection` phase stores this value in `result_ref`. It
  # holds only stable values: the declared tier order, the ordered tier-run
  # references, and the typed timing summary. The accepted snapshot lives in the
  # phase itself, so it is named once.
  #
  # A repeated acceptance may only rewrite the identical value, and a read-back
  # validates the handoff against the declared tiers and the stored tier runs.

  @schema_version 1

  @type t :: %__MODULE__{
          schema_version: integer(),
          tiers: [String.t()],
          runs: [Run.t()],
          timing: TimingSummary.t()
        }

  embedded_schema do
    field :schema_version, :integer
    field :tiers, {:array, :string}
    embeds_many :runs, Run, on_replace: :delete
    embeds_one :timing, TimingSummary, on_replace: :update
  end

  # Builds the handoff of one accepted collection. The runs are the stored tier
  # runs in declared order, so the value can be persisted and read back without
  # a second source of truth.
  @spec new([String.t()], [map()], TimingSummary.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def new(tiers, runs, %TimingSummary{} = timing) when is_list(tiers) and is_list(runs) do
    params = %{
      "schema_version" => @schema_version,
      "tiers" => tiers,
      "runs" => Enum.map(runs, &run_params/1),
      "timing" => TimingSummary.to_params(timing)
    }

    parse(params)
  end

  def new(_tiers, _runs, _timing), do: {:error, StudyError.incomplete_final_family()}

  # `to_params/1` comes from the shared contract codec, so the persisted shape
  # follows the declared field set of this schema and its embeds.

  @spec parse(term()) :: {:ok, t()} | {:error, StudyError.t()}
  def parse(%{"schema_version" => @schema_version} = params) do
    case materialize(params) do
      {:ok, %__MODULE__{} = handoff} -> validate_identities(handoff)
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  def parse(_params), do: {:error, StudyError.incomplete_final_family()}

  # The stored tier runs must equal the persisted references in both directions.
  @spec matches_runs?(t(), [map()]) :: boolean()
  def matches_runs?(%__MODULE__{runs: runs}, stored) when is_list(stored) do
    Enum.map(runs, &run_params/1) == Enum.map(stored, &run_params/1)
  end

  def matches_runs?(_handoff, _stored), do: false

  defp materialize(params) do
    case %__MODULE__{}
         |> changeset(params)
         |> apply_action(:validate) do
      {:ok, %__MODULE__{} = handoff} -> {:ok, handoff}
      {:error, %Ecto.Changeset{}} -> {:error, StudyError.incomplete_final_family()}
    end
  end

  defp changeset(handoff, attrs) do
    handoff
    |> cast(attrs, [:schema_version, :tiers])
    |> validate_required([:schema_version, :tiers])
    |> validate_number(:schema_version, equal_to: @schema_version)
    |> cast_embed(:runs, required: true)
    |> cast_embed(:timing, required: true)
  end

  # A handoff describes one complete ordered family: one run per declared tier,
  # in declared order, with one timing summary in the same order.
  defp validate_identities(%__MODULE__{} = handoff) do
    tiers = handoff.tiers
    runs = handoff.runs

    cond do
      not declared_tiers?(tiers) ->
        {:error, StudyError.incomplete_final_family()}

      Enum.map(runs, & &1.tier) != tiers ->
        {:error, StudyError.incomplete_final_family()}

      Enum.map(runs, & &1.tier_position) != positions(tiers) ->
        {:error, StudyError.incomplete_final_family()}

      not Enum.all?(runs, &positive_run?/1) ->
        {:error, StudyError.incomplete_final_family()}

      true ->
        timing_identity(handoff)
    end
  end

  defp timing_identity(%__MODULE__{tiers: tiers, timing: %TimingSummary{} = timing} = handoff) do
    case TimingSummary.validate_declared_order(timing, tiers) do
      :ok -> {:ok, handoff}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp declared_tiers?([_ | _] = tiers) do
    Enum.all?(tiers, &(is_binary(&1) and String.trim(&1) != "")) and
      Enum.uniq(tiers) == tiers
  end

  defp declared_tiers?(_tiers), do: false

  defp positions(tiers), do: Enum.to_list(0..(length(tiers) - 1))

  defp positive_run?(%Run{gust_run_id: run_id}), do: is_integer(run_id) and run_id > 0
  defp positive_run?(_run), do: false

  defp run_params(%Run{} = run) do
    %{
      "tier" => run.tier,
      "tier_position" => run.tier_position,
      "gust_run_id" => run.gust_run_id
    }
  end

  defp run_params(%{tier: tier, tier_position: position, gust_run_id: run_id}) do
    %{"tier" => tier, "tier_position" => position, "gust_run_id" => run_id}
  end
end
