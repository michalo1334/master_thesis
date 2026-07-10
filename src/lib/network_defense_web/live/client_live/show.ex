defmodule NetworkDefenseWeb.ClientLive.Show do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Clients

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Client {@client.id}
        <:subtitle>This is a client record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/clients"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/clients/#{@client}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit client
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@client.name}</:item>
        <:item title="Email">{@client.email}</:item>
        <:item title="Status">{@client.status}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Client")
     |> assign(:client, Clients.get_client!(id))}
  end
end
