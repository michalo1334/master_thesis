defmodule Fixture.Controls do
  def other_name(value), do: value

  def safe do
    try do
      :ok
    catch
      kind, _ when kind == :throw -> :ok
    end
  end

  defmodule Unrelated do
    defp node_type(value), do: value
  end
end
