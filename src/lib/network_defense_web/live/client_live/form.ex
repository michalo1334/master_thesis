defmodule NetworkDefenseWeb.ClientLive.Form do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Clients
  alias NetworkDefense.Clients.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage client records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="client-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:email]} type="text" label="Email" />
        <.input field={@form[:status]} type="text" label="Status" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Client</.button>
          <.button navigate={return_path(@return_to, @client)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    client = Clients.get_client!(id)

    socket
    |> assign(:page_title, "Edit Client")
    |> assign(:client, client)
    |> assign(:form, to_form(Clients.change_client(client)))
  end

  defp apply_action(socket, :new, _params) do
    client = %Client{}

    socket
    |> assign(:page_title, "New Client")
    |> assign(:client, client)
    |> assign(:form, to_form(Clients.change_client(client)))
  end

  @impl true
  def handle_event("validate", %{"client" => client_params}, socket) do
    changeset = Clients.change_client(socket.assigns.client, client_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"client" => client_params}, socket) do
    save_client(socket, socket.assigns.live_action, client_params)
  end

  defp save_client(socket, :edit, client_params) do
    case Clients.update_client(socket.assigns.client, client_params) do
      {:ok, client} ->
        {:noreply,
         socket
         |> put_flash(:info, "Client updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, client))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_client(socket, :new, client_params) do
    case Clients.create_client(client_params) do
      {:ok, client} ->
        {:noreply,
         socket
         |> put_flash(:info, "Client created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, client))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _client), do: ~p"/clients"
  defp return_path("show", client), do: ~p"/clients/#{client}"
end
