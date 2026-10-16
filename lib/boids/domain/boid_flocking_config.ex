defmodule Boids.BoidFlockingConfig do
  @moduledoc """
  This is a central domain module for all flocking related configurations.
  """

  @perception_radius 50
  @separation_radius 20

  @spec boid_perception_radius() :: pos_integer()
  def boid_perception_radius, do: @perception_radius

  @spec boid_separation_radius() :: pos_integer()
  def boid_separation_radius, do: @separation_radius
end
