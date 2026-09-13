defmodule Boids.Repo do
  use Ecto.Repo,
    otp_app: :boids,
    adapter: Ecto.Adapters.Postgres
end
