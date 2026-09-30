defmodule NetworkDefense.Evaluation.AnalysisLimits do
  @moduledoc """
  Owns the analysis ZIP byte limits.

  Both limits accept only positive integers. Any other configured value falls
  back to the module default, so a malformed setting cannot disable a limit.
  `max_zip_bytes/0` bounds the service round trip and the study bundle. Study
  bundling and analysis result parsing share this value so the two paths never
  disagree.

  `browser_result_bytes/0` is the conservative limit for the base64 result
  bytes sent to one browser document. It never exceeds `max_zip_bytes/0`,
  because the ready event encodes the ZIP as base64 and the LiveView pushes the
  string into the socket.
  """

  @default_max_zip_bytes 50 * 1024 * 1024
  @default_browser_result_bytes 4 * 1024 * 1024

  @spec default_max_zip_bytes() :: pos_integer()
  def default_max_zip_bytes, do: @default_max_zip_bytes

  @spec default_browser_result_bytes() :: pos_integer()
  def default_browser_result_bytes, do: @default_browser_result_bytes

  @doc """
  Returns the service ZIP limit as a positive integer.

  A missing, zero, negative, or non-integer value falls back to
  `default_max_zip_bytes/0`.
  """
  @spec max_zip_bytes() :: pos_integer()
  def max_zip_bytes, do: configured(:max_zip_bytes) |> positive_integer(@default_max_zip_bytes)

  @doc """
  Returns the browser-delivery byte limit for one study result ZIP.

  A malformed value falls back to `default_browser_result_bytes/0`. The result
  never exceeds `max_zip_bytes/0`, so one oversized result is rejected with
  `:result_too_large` before it becomes a base64 string in the socket.
  """
  @spec browser_result_bytes() :: pos_integer()
  def browser_result_bytes do
    configured(:browser_result_bytes)
    |> positive_integer(@default_browser_result_bytes)
    |> min(max_zip_bytes())
  end

  @doc "Reports whether a result ZIP fits the browser-delivery limit."
  @spec browser_deliverable?(term()) :: boolean()
  def browser_deliverable?(archive) when is_binary(archive),
    do: byte_size(archive) <= browser_result_bytes()

  def browser_deliverable?(_archive), do: false

  defp configured(key) do
    case Application.get_env(:network_defense, :analysis_service, []) do
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
      _other -> nil
    end
  end

  defp positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, fallback), do: fallback
end
