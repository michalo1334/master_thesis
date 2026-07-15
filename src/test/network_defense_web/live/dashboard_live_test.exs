defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the Svelte dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end

  test "publishes a canonical simulation command result", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_hook(view, "run_simulation", %{"document_id" => "topology-1"})

    assert render(view) =~ "Simulation result 1"
  end
end
