defmodule NetworkDefenseWeb.Web.Contracts.SaveGraph do
  @moduledoc false
  defmodule Payload do
    @moduledoc false
    defstruct [:graph]
  end

  defmodule Reply do
    @moduledoc false
    defstruct [:status]
  end
end
