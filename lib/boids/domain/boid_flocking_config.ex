defmodule Boids.BoidFlockingConfig do
  @moduledoc """
  This is a central domain module for all flocking related configurations.
  """

  @perception_radius 50

  @spec boid_perception_radius() :: pos_integer()
  def boid_perception_radius, do: @perception_radius
end
