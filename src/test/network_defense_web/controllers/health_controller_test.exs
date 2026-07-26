defmodule NetworkDefenseWeb.HealthControllerTest do
  use NetworkDefenseWeb.ConnCase, async: true

  test "reports liveness", %{conn: conn} do
    conn = get(conn, "/healthz")

    assert response(conn, 200) == "ok"
  end

  test "reports readiness when the database is available", %{conn: conn} do
    conn = get(conn, "/readyz")

    assert response(conn, 200) == "ok"
  end
end
