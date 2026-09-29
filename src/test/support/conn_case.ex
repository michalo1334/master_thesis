defmodule NetworkDefenseWeb.ConnCase do
  @moduledoc "Sets up connections and the database sandbox for web tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint NetworkDefenseWeb.Endpoint

      use NetworkDefenseWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import NetworkDefenseWeb.ConnCase
    end
  end

  setup tags do
    NetworkDefense.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
