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

  test "maps a warm-up archive request to 409", %{conn: conn} do
    alias NetworkDefense.Evaluation
    alias NetworkDefense.EvaluationFixtures

    manifest =
      EvaluationFixtures.analysis_manifest() |> put_in(["evaluation", "trials"], 1)

    manifest_id = "controller-warmup-#{System.unique_integer([:positive])}"
    assert {:ok, _manifest} = EvaluationFixtures.save_manifest(manifest_id, manifest)

    assert {:ok, warmup} = Evaluation.warm_up(manifest_id)
    assert warmup.status == "completed"

    conn = get(conn, "/evaluations/#{warmup.id}/download")

    assert response(conn, 409) == "evaluation run is a warm-up and cannot be exported"
  end
end
