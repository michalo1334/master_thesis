defmodule NetworkDefense.Evaluation.AnalysisLimits do
  @moduledoc """
  Owns the analysis ZIP byte limit.

  `max_zip_bytes/0` reads the configured `:analysis_service` limit and falls
  back to `default_max_zip_bytes/0`. Study bundling and analysis result parsing
  share this value so the two paths never disagree.
  """

  @default_max_zip_bytes 50 * 1024 * 1024

  @spec default_max_zip_bytes() :: pos_integer()
  def default_max_zip_bytes, do: @default_max_zip_bytes

  @spec max_zip_bytes() :: pos_integer()
  def max_zip_bytes do
    Application.get_env(:network_defense, :analysis_service, [])[:max_zip_bytes] ||
      @default_max_zip_bytes
  end
end
