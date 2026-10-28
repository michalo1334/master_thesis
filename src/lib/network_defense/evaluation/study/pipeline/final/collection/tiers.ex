defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Tiers do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.{IO, TierRunner}

  # The ordered tier family of Final collection.
  #
  # Tiers run one at a time, in declared order, and only after the previous tier
  # returned its measured timings. The family is accepted only when every
  # declared tier reported its own five measured positions.
  @spec run(IO.t(), keyword()) ::
          {:ok, map()} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{tiers: tiers} = io, opts) do
    result =
      tiers
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, %{}}, fn {tier, tier_position}, {:ok, collected} ->
        case TierRunner.run(io, tier, tier_position, opts) do
          {:ok, timings} ->
            collected =
              Map.put(collected, tier, %{tier_position: tier_position, timings: timings})

            {:cont, {:ok, collected}}

          other ->
            {:halt, other}
        end
      end)

    with {:ok, collected} <- result, :ok <- validate_family(collected, tiers) do
      {:ok, collected}
    end
  end

  # The timing family is keyed by declared tier and holds one complete measured
  # family per tier. A missing, duplicated, or out-of-order tier fails here.
  @spec validate_family(term(), [String.t()]) :: :ok | {:error, StudyError.t()}
  def validate_family(collected, tiers) when is_map(collected) and is_list(tiers) do
    valid? =
      Map.keys(collected) |> Enum.sort() == Enum.sort(tiers) and
        tiers
        |> Enum.with_index()
        |> Enum.all?(fn {tier, position} ->
          case Map.fetch(collected, tier) do
            {:ok, %{tier_position: ^position, timings: timings}} -> measured_family?(timings)
            _missing -> false
          end
        end)

    if valid?, do: :ok, else: {:error, StudyError.final_timing_incomplete()}
  end

  def validate_family(_collected, _tiers), do: {:error, StudyError.final_timing_incomplete()}

  defp measured_family?([_, _, _, _, _]), do: true
  defp measured_family?(_timings), do: false
end
