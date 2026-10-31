defmodule NetworkDefense.Evaluation2.Study.Final.TierContract do
  @moduledoc """
  Transport contract of one Final tier collection Gust run.

  The phase run identifies the tier plan, and the terminal result proves the
  measured work of the five replicas of that tier. The result carries durations
  only, because raw clock readings stay in the clock process. A stored result
  therefore rebuilds the same measured values after the clock is gone.

  The transport is strict, because a stored run input and a stored terminal
  result cross the Gust JSON boundary:

    * the run input carries one canonical phase-run UUID under
      `"study_phase_run_id"`;
    * the terminal result carries the canonical phase-run UUID, the tier name,
      the clock-session identity, and the timing of the five measured replicas.

  ```json
  {
    "study_phase_run_id": "<canonical UUID>",
    "tier": "medium",
    "clock_session": "<clock-session identity>",
    "timing": {
      "replicas": [
        {"replica_position": 0, "plan_selection_us": 120, "simulation_us": 480, "total_us": 600}
      ]
    }
  }
  ```

  The replica list holds exactly five entries, one per measured position `0..4`,
  in ascending order. Each entry holds nonnegative integer microseconds where
  `total_us` equals `plan_selection_us + simulation_us`. Warm-up stays outside
  the receipt. Any other input or output value fails.
  """

  alias NetworkDefense.Evaluation2.Study.Final.TierContract.{Input, Output}
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier, as: TimingTier
  alias NetworkDefense.Evaluation2.Study.Tier

  @typedoc "One JSON-safe Gust parameter object."
  @type params :: %{required(String.t()) => term()}

  @measured_positions [0, 1, 2, 3, 4]

  # Sorted key sets make the stored shape canonical in both directions.
  @output_keys ["clock_session", "study_phase_run_id", "tier", "timing"]
  @timing_keys ["replicas"]
  @replica_keys ["plan_selection_us", "replica_position", "simulation_us", "total_us"]

  # The three values belong to one replica, so the total must be their sum.
  defguardp is_elapsed(plan_selection_us, simulation_us, total_us)
            when is_integer(plan_selection_us) and plan_selection_us >= 0 and
                   is_integer(simulation_us) and simulation_us >= 0 and
                   is_integer(total_us) and total_us == plan_selection_us + simulation_us

  @doc """
  Encode the root input of one Final tier run as JSON-safe run parameters.
  """
  @spec to_params(Input.t()) :: params()
  def to_params(%Input{phase_run_id: phase_run_id}),
    do: %{"study_phase_run_id" => phase_run_id}

  @doc """
  Decode the stored input of one Final tier run.

  Only the canonical lower-case UUID form is accepted, so a decoded input names
  exactly one stored phase run.
  """
  @spec decode_input(map()) :: {:ok, Input.t()} | :error
  def decode_input(%{"study_phase_run_id" => phase_run_id} = params) when map_size(params) == 1 do
    case canonical_uuid(phase_run_id) do
      {:ok, phase_run_id} -> {:ok, %Input{phase_run_id: phase_run_id}}
      :error -> :error
    end
  end

  def decode_input(_params), do: :error

  @doc """
  Encode the terminal result of one Final tier run as a JSON-safe result.

  The caller that stores the run result owns this step, so the terminal task and
  the run completion keep one stored shape.
  """
  @spec encode_output(Output.t()) :: {:ok, params()} | :error
  def encode_output(%Output{} = output) do
    with {:ok, phase_run_id} <- canonical_uuid(output.phase_run_id),
         {:ok, tier} <- encode_tier(output.tier),
         {:ok, clock_session} <- clock_session(output.clock_session),
         {:ok, replicas} <- encode_timing(output.timing) do
      {:ok,
       %{
         "study_phase_run_id" => phase_run_id,
         "tier" => tier,
         "clock_session" => clock_session,
         "timing" => %{"replicas" => replicas}
       }}
    end
  end

  def encode_output(_output), do: :error

  @doc """
  Decode the stored terminal result of one Final tier run.

  A stored result that does not match the declared shape fails, so an old or
  foreign payload never becomes a tier receipt.
  """
  @spec decode_output(map()) :: {:ok, Output.t()} | :error
  def decode_output(%{"study_phase_run_id" => _phase_run_id} = params) do
    with true <- exact_keys?(params, @output_keys),
         {:ok, phase_run_id} <- canonical_uuid(Map.fetch!(params, "study_phase_run_id")),
         {:ok, tier} <- decode_tier(Map.fetch!(params, "tier")),
         {:ok, clock_session} <- clock_session(Map.fetch!(params, "clock_session")),
         {:ok, timing} <- decode_timing(Map.fetch!(params, "timing")) do
      {:ok,
       %Output{
         phase_run_id: phase_run_id,
         tier: tier,
         clock_session: clock_session,
         timing: timing
       }}
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

  # --- tier --------------------------------------------------------------

  # The closed tier order of Study.Tier owns the accepted names.
  defp encode_tier(tier) when is_atom(tier) do
    case Enum.find(Tier.all(), fn declared -> declared == tier end) do
      nil -> :error
      declared -> {:ok, Atom.to_string(declared)}
    end
  end

  defp encode_tier(_tier), do: :error

  defp decode_tier("small"), do: {:ok, :small}
  defp decode_tier("medium"), do: {:ok, :medium}
  defp decode_tier("large"), do: {:ok, :large}
  defp decode_tier(_tier), do: :error

  # --- clock session -----------------------------------------------------

  # Both directions apply one rule: the identity is a nonempty UTF-8 string.
  defp clock_session(session) when is_binary(session) and byte_size(session) > 0 do
    if String.valid?(session), do: {:ok, session}, else: :error
  end

  defp clock_session(_session), do: :error

  # --- timing ------------------------------------------------------------

  defp encode_timing(%TimingTier{replicas: replicas}) when is_map(replicas) do
    if measured?(replicas) do
      @measured_positions
      |> Enum.map(fn position -> encode_replica(position, Map.fetch!(replicas, position)) end)
      |> collect()
    else
      :error
    end
  end

  defp encode_timing(_timing), do: :error

  defp decode_timing(%{"replicas" => entries} = params) when is_list(entries) do
    with true <- exact_keys?(params, @timing_keys),
         {:ok, replicas} <- decode_replicas(entries) do
      {:ok, %TimingTier{replicas: replicas}}
    else
      _rejected -> :error
    end
  end

  defp decode_timing(_timing), do: :error

  # Ascending positions keep the stored order canonical and reject duplicates.
  defp decode_replicas(entries) do
    case collect(Enum.map(entries, &decode_replica/1)) do
      {:ok, pairs} ->
        if Enum.map(pairs, &elem(&1, 0)) == @measured_positions do
          {:ok, Map.new(pairs)}
        else
          :error
        end

      :error ->
        :error
    end
  end

  defp encode_replica(
         position,
         %Replica{
           plan_selection_us: plan_selection_us,
           simulation_us: simulation_us,
           total_us: total_us
         }
       )
       when position in @measured_positions and
              is_elapsed(plan_selection_us, simulation_us, total_us) do
    {:ok,
     %{
       "replica_position" => position,
       "plan_selection_us" => plan_selection_us,
       "simulation_us" => simulation_us,
       "total_us" => total_us
     }}
  end

  defp encode_replica(_position, _replica), do: :error

  defp decode_replica(
         %{
           "replica_position" => position,
           "plan_selection_us" => plan_selection_us,
           "simulation_us" => simulation_us,
           "total_us" => total_us
         } = params
       )
       when is_integer(position) and position in @measured_positions and
              is_elapsed(plan_selection_us, simulation_us, total_us) do
    if exact_keys?(params, @replica_keys) do
      {:ok,
       {position,
        %Replica{
          plan_selection_us: plan_selection_us,
          simulation_us: simulation_us,
          total_us: total_us
        }}}
    else
      :error
    end
  end

  defp decode_replica(_replica), do: :error

  defp measured?(replicas), do: Enum.sort(Map.keys(replicas)) == @measured_positions

  # --- shared helpers ----------------------------------------------------

  defp exact_keys?(params, expected_keys), do: Enum.sort(Map.keys(params)) == expected_keys

  # One unusable replica rejects the whole stored value, so a partial replica
  # list never reaches summation or reporting.
  @spec collect([{:ok, value} | :error]) :: {:ok, [value]} | :error when value: var
  defp collect(results) do
    if Enum.all?(results, &match?({:ok, _value}, &1)) do
      {:ok, Enum.map(results, fn {:ok, value} -> value end)}
    else
      :error
    end
  end

  # Only the canonical lower-case form names one stored record.
  @spec canonical_uuid(term()) :: {:ok, Ecto.UUID.t()} | :error
  defp canonical_uuid(value) when is_binary(value) do
    if Ecto.UUID.cast(value) == {:ok, value}, do: {:ok, value}, else: :error
  end

  defp canonical_uuid(_value), do: :error
end
