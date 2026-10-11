defmodule Boids.BoidMock do
  @behaviour Boids.BoidBehaviour
  alias Boids.Boid

  def new() do
    %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
  end

  def advance_boid(%Boid{}) do
    %Boid{position: {1.0, 1.0}, velocity: {1.0, 1.0}}
  end
end
