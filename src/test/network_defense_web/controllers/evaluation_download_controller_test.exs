defmodule NetworkDefenseWeb.EvaluationDownloadControllerTest do
  use NetworkDefenseWeb.ConnCase, async: true

  test "returns not found for a malformed run id", %{conn: conn} do
    conn = get(conn, "/evaluations/not-a-uuid/download")

    assert response(conn, 404) == "evaluation run not found"
  end

  test "returns not found for an unknown run id", %{conn: conn} do
    conn = get(conn, "/evaluations/#{Ecto.UUID.generate()}/download")

    assert response(conn, 404) == "evaluation run not found"
  end
end
