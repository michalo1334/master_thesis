defmodule NetworkDefense.Evaluation.Study.CollectionLimits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @keys [:max_phase_items, :max_gust_concurrency]

  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{
          max_phase_items: pos_integer(),
          max_gust_concurrency: pos_integer()
        }

  @spec keys() :: [atom()]
  def keys, do: @keys

  @spec fetch() :: {:ok, t()} | {:error, StudyError.t()}
  def fetch do
    case Application.fetch_env(:network_defense, __MODULE__) do
      {:ok, config} -> parse(config)
      :error -> {:error, StudyError.collection_configuration_invalid()}
    end
  end

  defp parse(config) when is_map(config) do
    if Enum.sort(Map.keys(config)) == Enum.sort(@keys),
      do: read_values(config),
      else: invalid()
  end

  defp parse(config) when is_list(config) do
    if Keyword.keyword?(config) and
         Enum.sort(config |> Keyword.keys() |> Enum.uniq()) == Enum.sort(@keys),
       do: read_values(Map.new(config)),
       else: invalid()
  end

  defp parse(_config), do: invalid()

  defp read_values(config) do
    if Enum.all?(@keys, fn key -> positive_integer?(Map.get(config, key)) end) do
      {:ok, struct!(__MODULE__, Map.take(config, @keys))}
    else
      invalid()
    end
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp invalid, do: {:error, StudyError.collection_configuration_invalid()}
end
