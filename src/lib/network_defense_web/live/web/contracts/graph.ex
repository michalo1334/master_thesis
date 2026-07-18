defmodule NetworkDefenseWeb.Web.Contracts.Graph do
  @moduledoc false
  defmodule Contract do
    @moduledoc false
    defstruct [:id, :title, :nodes, :edges, :lock_version]
  end

  defmodule Node do
    @moduledoc false
    defstruct [:id, :type, :data, :view_data]
  end

  defmodule NodeViewData do
    @moduledoc false
    defstruct [:x_pos, :y_pos]
  end

  defmodule Edge do
    @moduledoc false
    defstruct [:id, :from_id, :to_id, :type, :data]
  end
end
