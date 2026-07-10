defmodule NetworkDefense.Repo do
  use Ecto.Repo,
    otp_app: :network_defense,
    adapter: Ecto.Adapters.Postgres
end
