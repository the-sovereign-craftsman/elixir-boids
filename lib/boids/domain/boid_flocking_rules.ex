defmodule Boids.BoidFlockingRules do
  @moduledoc """
  Decides which way a boid should steer, given its neighbors.

  `combined_steering_vector/3` is the entry point: it runs every rule, weights
  each one, and sums them into a single steering vector. `Boids.Boid` adds that
  vector to the boid's velocity and handles the movement; it doesn't know which
  rules exist or how they are weighted.

  Each rule is also public and returns an unweighted vector, so its geometry can
  be tested on its own. Every rule looks at the same boid and the same neighbors
  independently; no rule uses another's result.

  Weights default to `Boids.BoidFlockingConfig`, but can be passed in, so they
  can change at runtime. A weight of 0 turns a rule off.
  """

  alias Boids.Boid
  alias Boids.BoidFlockingConfig

  @separation_radius_squared BoidFlockingConfig.boid_separation_radius() ** 2

  @default_weights %{
    separation: BoidFlockingConfig.boid_separation_weight(),
    cohesion: BoidFlockingConfig.boid_cohesion_weight()
  }

  @typedoc "Which way, and how strongly, a rule wants to push a boid: `{x, y}`."
  @type steering_vector :: {float(), float()}

  @typedoc "How strongly each rule counts towards the combined steering. 0 turns a rule off."
  @type weights :: %{separation: number(), cohesion: number()}

  @doc "The weights from `Boids.BoidFlockingConfig`."
  @spec default_weights() :: weights()
  def default_weights, do: @default_weights

  @doc """
  Runs every rule, multiplies each rule's vector by its weight, and sums them
  into the single steering vector for this tick.
  """
  @spec combined_steering_vector(Boid.t(), [Boid.t()], weights()) :: steering_vector()
  def combined_steering_vector(boid, neighbors, weights \\ default_weights()) do
    {separation_x, separation_y} = separation_steering_vector(boid, neighbors)
    {cohesion_x, cohesion_y} = cohesion_steering_vector(boid, neighbors)

    {separation_x * weights.separation + cohesion_x * weights.cohesion,
     separation_y * weights.separation + cohesion_y * weights.cohesion}
  end

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
