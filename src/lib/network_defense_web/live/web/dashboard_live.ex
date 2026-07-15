defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <.svelte
        name="Dashboard"
        id="dashboard"
        props={%{serverCommand: @server_command}}
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, server_command: nil, command_version: 0)}
  end

  @impl true
  def handle_event("run_simulation", %{"document_id" => document_id}, socket)
      when is_binary(document_id) and byte_size(document_id) > 0 do
    command_version = socket.assigns.command_version + 1

    server_command = %{
      version: command_version,
      command: "run_simulation",
      documentId: "simulation-#{command_version}",
      title: "Simulation result #{command_version}",
      message: "Simulation result is ready."
    }

    {:reply, server_command,
     assign(socket, server_command: server_command, command_version: command_version)}
  end

  def handle_event("run_simulation", _params, socket) do
    {:reply, %{error: "A topology document is required to run a simulation."}, socket}
  end

  @impl true
  def handle_event("optimize_defense", %{"document_id" => document_id}, socket)
      when is_binary(document_id) and byte_size(document_id) > 0 do
    command_version = socket.assigns.command_version + 1

    server_command = %{
      version: command_version,
      command: "optimize_defense",
      message: "Defense optimization has been queued."
    }

    {:reply, server_command,
     assign(socket, server_command: server_command, command_version: command_version)}
  end

  def handle_event("optimize_defense", _params, socket) do
    {:reply, %{error: "A topology document is required to optimize defenses."}, socket}
  end
end
