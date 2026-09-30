defmodule NetworkDefense.Evaluation.StudyTierValidator do
  @moduledoc """
  Validates study tier run identities in one place.

  The Mix task, `NetworkDefense.Evaluation.analyze_study/3`, and
  `NetworkDefense.Evaluation.StudyBundle.archive/2` all pass tiers here. This
  module accepts the tuple form from the Mix task and the map form from archive
  construction. It checks the shape, the label, the UUID run ID, and duplicate
  labels and run IDs.

  `normalize/1` turns the contextual `:invalid_run_id` tuple into the
  `:invalid_run_id` atom. Match the raw error when you must name the failing
  tier.
  """

  @label_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/
  @forbidden_label_fragments ["/", "\\", ".."]

  @type tier ::
          {String.t(), String.t()}
          | %{required(:tier) => String.t(), required(:run_id) => String.t()}

  @type error ::
          :no_tiers
          | :invalid_tier
          | :unsafe_tier_label
          | :duplicate_tier_label
          | :duplicate_run_id
          | {:invalid_run_id, term()}

  @spec validate([tier()]) :: :ok | {:error, error()}
  def validate([]), do: {:error, :no_tiers}

  def validate(tiers) when is_list(tiers) do
    with {:ok, pairs} <- pairs(tiers) do
      unique(pairs)
    end
  end

  def validate(_tiers), do: {:error, :invalid_tier}

  @spec normalize(:ok | {:error, error()}) :: :ok | {:error, atom()}
  def normalize(:ok), do: :ok
  def normalize({:error, {:invalid_run_id, _entry}}), do: {:error, :invalid_run_id}
  def normalize({:error, reason}) when is_atom(reason), do: {:error, reason}

  defp pairs(tiers) do
    tiers
    |> Enum.reduce_while({:ok, []}, fn tier, {:ok, acc} ->
      case pair(tier) do
        {:ok, pair} -> {:cont, {:ok, [pair | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      {:error, _reason} = error -> error
    end
  end

  defp pair({label, run_id}), do: fields(label, run_id, {label, run_id})
  defp pair(%{tier: label, run_id: run_id}), do: fields(label, run_id, {label, run_id})
  defp pair(_other), do: {:error, :invalid_tier}

  defp fields(label, run_id, context) do
    cond do
      not safe_label?(label) -> {:error, :unsafe_tier_label}
      not uuid?(run_id) -> {:error, {:invalid_run_id, context}}
      true -> {:ok, {label, run_id}}
    end
  end

  @doc """
  Reports whether a tier label is safe for archive member names.

  Shared with the saved-specification contract so declared labels cannot
  become unsafe archive paths.
  """
  @spec safe_label?(term()) :: boolean()
  def safe_label?(label) when is_binary(label) do
    label != "" and
      not String.contains?(label, @forbidden_label_fragments) and
      String.match?(label, @label_pattern)
  end

  def safe_label?(_label), do: false

  defp uuid?(value) when is_binary(value) and value != "",
    do: match?({:ok, _}, Ecto.UUID.cast(value))

  defp uuid?(_value), do: false

  defp unique(pairs) do
    labels = Enum.map(pairs, &elem(&1, 0))
    run_ids = Enum.map(pairs, &elem(&1, 1))

    cond do
      length(labels) != length(Enum.uniq(labels)) -> {:error, :duplicate_tier_label}
      length(run_ids) != length(Enum.uniq(run_ids)) -> {:error, :duplicate_run_id}
      true -> :ok
    end
  end
end
