defmodule NetworkDefenseWeb.Web.Contracts.LayoutGraph do
  @moduledoc false

  defmodule LayoutParams do
    @moduledoc false
    defstruct [:iterations, :spring_length, :repulsion]

    def new(%{"iterations" => it, "springLength" => sl, "repulsion" => r})
        when is_integer(it) and is_integer(sl) and is_integer(r) do
      %__MODULE__{iterations: it, spring_length: sl, repulsion: r}
    end

    def new(map) when is_map(map),
      do: raise(ArgumentError, "invalid layout params: #{inspect(map)}")
  end

  defmodule Payload do
    @moduledoc false
    defstruct [:graph, :params]
  end

  defmodule Reply do
    @moduledoc false
    defstruct [:status, :graph]
  end
end
