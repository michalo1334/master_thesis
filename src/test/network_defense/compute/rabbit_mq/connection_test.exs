defmodule NetworkDefense.Compute.RabbitMQ.ConnectionTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.RabbitMQ.Connection

  test "starts the named connection process" do
    assert is_pid(Process.whereis(Connection))
  end
end
