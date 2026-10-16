defmodule Boids.BoidFlockingRules do
  @moduledoc """
  The flocking rules, each a pure function from a boid and its neighbors to a
  steering vector.

  Every rule looks at the same boid and the same neighbors independently; no
  rule uses another's result. The vectors returned here are unweighted:
  `Boids.Boid.advance_boid/2` multiplies each by its weight from
  `Boids.BoidFlockingConfig`, adds them to the boid's velocity, and limits the
  speed.
  """

  alias Boids.Boid
  alias Boids.BoidFlockingConfig

  @separation_radius_squared BoidFlockingConfig.boid_separation_radius() ** 2

  @typedoc "Which way, and how strongly, a rule wants to push a boid: `{x, y}`."
  @type steering_vector :: {float(), float()}

  @doc """
  Pushes the boid away from neighbors inside the separation radius.

  Each close neighbor pushes directly away from itself with strength
  `1 / distance`, so nearer neighbors push harder. The pushes are summed, not
  averaged, so more crowding means a stronger push. Neighbors at exactly the
  boid's position are skipped, since they give no direction to push in.
  """
  @spec separation_steering_vector(Boid.t(), [Boid.t()]) :: steering_vector()
  def separation_steering_vector(%Boid{position: {x, y}}, neighbors) do
    neighbors
    |> Enum.map(fn %Boid{position: {neighbor_x, neighbor_y}} ->
      away_x = x - neighbor_x
      away_y = y - neighbor_y
      distance_squared = away_x * away_x + away_y * away_y
      {away_x, away_y, distance_squared}
    end)
    |> Enum.filter(fn {_away_x, _away_y, distance_squared} ->
      distance_squared > 0 and distance_squared <= @separation_radius_squared
    end)
    |> Enum.map(fn {away_x, away_y, distance_squared} ->
      {away_x / distance_squared, away_y / distance_squared}
    end)
    |> Enum.reduce({0.0, 0.0}, fn {repulsion_x, repulsion_y}, {total_x, total_y} ->
      {total_x + repulsion_x, total_y + repulsion_y}
    end)
  end

  @doc """
  Pulls the boid toward the center (average position) of its neighbors.

  The vector points from the boid to that center, so it is longer the farther
  the boid is from the group. With no neighbors there is no center, so there
  is no pull.
  """
  @spec cohesion_steering_vector(Boid.t(), [Boid.t()]) :: steering_vector()
  def cohesion_steering_vector(_boid, []), do: {0.0, 0.0}

  def cohesion_steering_vector(%Boid{position: {x, y}}, neighbors) do
    {sum_x, sum_y} =
      Enum.reduce(neighbors, {0.0, 0.0}, fn neighbor, {total_x, total_y} ->
        {neighbor_x, neighbor_y} = neighbor.position
        {total_x + neighbor_x, total_y + neighbor_y}
      end)

    neighbor_count = length(neighbors)

    {sum_x / neighbor_count - x, sum_y / neighbor_count - y}
  end
end
