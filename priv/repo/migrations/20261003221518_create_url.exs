defmodule Boids.Repo.Migrations.CreateUrl do
  use Ecto.Migration

  def change do
    create table(:url) do
      add :link, :string
      add :title, :string

      timestamps(type: :utc_datetime)
    end
  end
end
