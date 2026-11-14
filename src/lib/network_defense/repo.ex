defmodule NetworkDefense.Repo do
  use Boundary, top_level?: true

  use Ecto.Repo,
    otp_app: :network_defense,
    adapter: Ecto.Adapters.Postgres
end
