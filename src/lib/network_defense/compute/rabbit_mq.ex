defmodule NetworkDefense.Compute.RabbitMQ do
  @moduledoc false

  use Boundary,
    deps: [NetworkDefense],
    exports: [Connection, Envelope, Worker]
end
