defmodule Fixture.ExitCatch do
  def run do
    try do
      :work
    catch
      :exit, _reason -> :ok
    end
  end
end
