# defmodule NetworkDefenseWeb.ClientLiveTest do
#   use NetworkDefenseWeb.ConnCase

#   import Phoenix.LiveViewTest
#   import NetworkDefense.ClientsFixtures

#   @create_attrs %{name: "some name", status: "some status", email: "some email"}
#   @update_attrs %{name: "some updated name", status: "some updated status", email: "some updated email"}
#   @invalid_attrs %{name: nil, status: nil, email: nil}
#   defp create_client(_) do
#     client = client_fixture()

#     %{client: client}
#   end

#   describe "Index" do
#     setup [:create_client]

#     test "lists all clients", %{conn: conn, client: client} do
#       {:ok, _index_live, html} = live(conn, ~p"/clients")

#       assert html =~ "Listing Clients"
#       assert html =~ client.name
#     end

#     test "saves new client", %{conn: conn} do
#       {:ok, index_live, _html} = live(conn, ~p"/clients")

#       assert {:ok, form_live, _} =
#                index_live
#                |> element("a", "New Client")
#                |> render_click()
#                |> follow_redirect(conn, ~p"/clients/new")

#       assert render(form_live) =~ "New Client"

#       assert form_live
#              |> form("#client-form", client: @invalid_attrs)
#              |> render_change() =~ "can&#39;t be blank"

#       assert {:ok, index_live, _html} =
#                form_live
#                |> form("#client-form", client: @create_attrs)
#                |> render_submit()
#                |> follow_redirect(conn, ~p"/clients")

#       html = render(index_live)
#       assert html =~ "Client created successfully"
#       assert html =~ "some name"
#     end

#     test "updates client in listing", %{conn: conn, client: client} do
#       {:ok, index_live, _html} = live(conn, ~p"/clients")

#       assert {:ok, form_live, _html} =
#                index_live
#                |> element("#clients-#{client.id} a", "Edit")
#                |> render_click()
#                |> follow_redirect(conn, ~p"/clients/#{client}/edit")

#       assert render(form_live) =~ "Edit Client"

#       assert form_live
#              |> form("#client-form", client: @invalid_attrs)
#              |> render_change() =~ "can&#39;t be blank"

#       assert {:ok, index_live, _html} =
#                form_live
#                |> form("#client-form", client: @update_attrs)
#                |> render_submit()
#                |> follow_redirect(conn, ~p"/clients")

#       html = render(index_live)
#       assert html =~ "Client updated successfully"
#       assert html =~ "some updated name"
#     end

#     test "deletes client in listing", %{conn: conn, client: client} do
#       {:ok, index_live, _html} = live(conn, ~p"/clients")

#       assert index_live |> element("#clients-#{client.id} a", "Delete") |> render_click()
#       refute has_element?(index_live, "#clients-#{client.id}")
#     end
#   end

#   describe "Show" do
#     setup [:create_client]

#     test "displays client", %{conn: conn, client: client} do
#       {:ok, _show_live, html} = live(conn, ~p"/clients/#{client}")

#       assert html =~ "Show Client"
#       assert html =~ client.name
#     end

#     test "updates client and returns to show", %{conn: conn, client: client} do
#       {:ok, show_live, _html} = live(conn, ~p"/clients/#{client}")

#       assert {:ok, form_live, _} =
#                show_live
#                |> element("a", "Edit")
#                |> render_click()
#                |> follow_redirect(conn, ~p"/clients/#{client}/edit?return_to=show")

#       assert render(form_live) =~ "Edit Client"

#       assert form_live
#              |> form("#client-form", client: @invalid_attrs)
#              |> render_change() =~ "can&#39;t be blank"

#       assert {:ok, show_live, _html} =
#                form_live
#                |> form("#client-form", client: @update_attrs)
#                |> render_submit()
#                |> follow_redirect(conn, ~p"/clients/#{client}")

#       html = render(show_live)
#       assert html =~ "Client updated successfully"
#       assert html =~ "some updated name"
#     end
#   end
# end
