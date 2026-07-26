defmodule NetworkDefenseWeb.HealthController do
  use NetworkDefenseWeb, :controller

  def live(conn, _params), do: send_resp(conn, 200, "ok")

  def ready(conn, _params) do
    case NetworkDefense.Repo.query("SELECT 1") do
      {:ok, _result} -> send_resp(conn, 200, "ok")
      {:error, _reason} -> send_resp(conn, 503, "database unavailable")
    end
  end
end
