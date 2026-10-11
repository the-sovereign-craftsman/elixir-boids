defmodule Boids.BoidBehaviour do
  alias Boids.Boid

  @callback new() :: Boid.t()

  @callback advance_boid(Boid.t()) :: Boid.t()
end
