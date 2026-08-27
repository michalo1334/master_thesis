defmodule NetworkDefenseWeb.EvaluationDownloadController do
  @moduledoc """
  Serves the output-contract ZIP for a completed evaluation run.

  The archive is generated in memory from the run and its linked execution
  rows. No artifact is stored permanently.
  """

  use NetworkDefenseWeb, :controller

  alias NetworkDefense.Evaluation

  def download(conn, %{"run_id" => run_id}) do
    case Ecto.UUID.cast(run_id) do
      {:ok, _uuid} -> do_download(conn, run_id)
      :error -> send_resp(conn, 404, "evaluation run not found")
    end
  end

  defp do_download(conn, run_id) do
    case Evaluation.download_archive(run_id) do
      {:ok, zip_binary, filename} ->
        conn
        |> put_resp_content_type("application/zip")
        |> send_download({:binary, zip_binary}, filename: filename)

      {:error, :not_found} ->
        send_resp(conn, 404, "evaluation run not found")

      {:error, :not_exportable} ->
        send_resp(conn, 409, "evaluation run is a warm-up and cannot be exported")

      {:error, :incomplete} ->
        send_resp(conn, 409, "evaluation run is not complete")

      {:error, _reason} ->
        send_resp(conn, 500, "unable to generate evaluation archive")
    end
  end
end
