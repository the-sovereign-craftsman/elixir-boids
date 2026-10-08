defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def spawn_boid(args) do
    DynamicSupervisor.start_child(Boids.DynamicSupervisor, {Boids.Boid, args})
  end
end
