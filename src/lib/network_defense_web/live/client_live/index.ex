defmodule NetworkDefenseWeb.ClientLive.Index do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Clients

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Clients
        <:actions>
          <.button variant="primary" navigate={~p"/clients/new"}>
            <.icon name="hero-plus" /> New Client
          </.button>
        </:actions>
      </.header>

      <.table
        id="clients"
        rows={@streams.clients}
        row_click={fn {_id, client} -> JS.navigate(~p"/clients/#{client}") end}
      >
        <:col :let={{_id, client}} label="Name">{client.name}</:col>
        <:col :let={{_id, client}} label="Email">{client.email}</:col>
        <:col :let={{_id, client}} label="Status">{client.status}</:col>
        <:action :let={{_id, client}}>
          <div class="sr-only">
            <.link navigate={~p"/clients/#{client}"}>Show</.link>
          </div>
          <.link navigate={~p"/clients/#{client}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, client}}>
          <.link
            phx-click={JS.push("delete", value: %{id: client.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Clients")
     |> stream(:clients, list_clients())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    client = Clients.get_client!(id)
    {:ok, _} = Clients.delete_client(client)

    {:noreply, stream_delete(socket, :clients, client)}
  end

  defp list_clients() do
    Clients.list_clients()
  end
end
