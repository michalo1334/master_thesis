defmodule NetworkDefenseWeb.MetricsPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "GET", request_path: "/metrics"} = conn, _opts) do
    body = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> Plug.Conn.put_resp_content_type("text/plain; version=0.0.4")
    |> Plug.Conn.send_resp(200, body)
    |> Plug.Conn.halt()
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.send_resp(404, "not found")
    |> Plug.Conn.halt()
  end
end
