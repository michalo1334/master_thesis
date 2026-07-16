defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the Svelte dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end

  test "dashboard root is present after run_simulation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_hook(view, "run_simulation", %{"document_id" => "topology-1"})

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end

  test "dashboard root is present after optimize_defense", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_hook(view, "optimize_defense", %{"document_id" => "topology-1"})

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end

  test "run_simulation is safely accepted without document_id", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_hook(view, "run_simulation", %{})

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end

  test "optimize_defense is safely accepted without document_id", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_hook(view, "optimize_defense", %{})

    assert has_element?(view, "#dashboard[data-name='Dashboard']")
  end
end
