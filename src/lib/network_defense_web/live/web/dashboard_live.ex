defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <.svelte
        name="Dashboard"
        id="dashboard"
        props={%{}}
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("run_simulation", %{"document_id" => document_id}, socket)
      when is_binary(document_id) and byte_size(document_id) > 0 do
    {:noreply, socket}
  end

  def handle_event("run_simulation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("optimize_defense", %{"document_id" => document_id}, socket)
      when is_binary(document_id) and byte_size(document_id) > 0 do
    {:noreply, socket}
  end

  def handle_event("optimize_defense", _params, socket) do
    {:noreply, socket}
  end
end
