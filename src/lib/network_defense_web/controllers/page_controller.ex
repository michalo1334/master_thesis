defmodule NetworkDefenseWeb.PageController do
  use NetworkDefenseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
