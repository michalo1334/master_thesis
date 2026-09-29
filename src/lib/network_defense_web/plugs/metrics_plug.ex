defmodule NetworkDefenseWeb.MetricsPlug do
  @moduledoc false

  @behaviour Plug

  alias Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "GET", request_path: "/metrics"} = conn, _opts) do
    body = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> Conn.put_resp_content_type("text/plain; version=0.0.4")
    |> Conn.send_resp(200, body)
    |> Conn.halt()
  end

  def call(conn, _opts) do
    conn
    |> Conn.send_resp(404, "not found")
    |> Conn.halt()
  end
end
