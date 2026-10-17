defmodule Boids.BoidFlockingConfig do
  @moduledoc """
  This is a central domain module for all flocking related configurations.
  """

  @boid_initial_speed 2
  @perception_radius 50
  @separation_radius 20
  @separation_weight 10
  @cohesion_weight 0.01
  @alignment_weight 0.05
  @boid_min_speed 2
  @boid_max_speed 4

  @spec boid_initial_speed() :: pos_integer()
  def boid_initial_speed, do: @boid_initial_speed

  @spec boid_perception_radius() :: pos_integer()
  def boid_perception_radius, do: @perception_radius

  @spec boid_separation_radius() :: pos_integer()
  def boid_separation_radius, do: @separation_radius

  @spec boid_separation_weight() :: pos_integer()
  def boid_separation_weight, do: @separation_weight

  @spec boid_cohesion_weight() :: float()
  def boid_cohesion_weight, do: @cohesion_weight

  @spec boid_alignment_weight() :: float()
  def boid_alignment_weight, do: @alignment_weight

  @spec boid_min_speed() :: pos_integer()
  def boid_min_speed, do: @boid_min_speed

  @spec boid_max_speed() :: pos_integer()
  def boid_max_speed, do: @boid_max_speed
end
