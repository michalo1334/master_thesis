defmodule NetworkDefenseWeb.Web.Contracts.OpenGraph do
  @moduledoc false
  defmodule Payload do
    @moduledoc false
    defstruct [:graph_id]
  end

  defmodule Reply do
    @moduledoc false
    defstruct [:status, :graph]
  end
end
