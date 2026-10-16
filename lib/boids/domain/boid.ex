defmodule Boids.Boid do
  @moduledoc """
  Pure domain model of a single boid: its position and velocity, and how it
  moves one step.

  Contains no processes or state. `Boids.BoidServer` holds a `%Boid{}` and
  calls `advance_boid/2` on every tick. Boids that reach the edge of the
  `Boids.World` arena are clamped to the wall and bounce back.
  """

  @behaviour Boids.BoidBehaviour

  alias Boids.BoidFlockingConfig

  @world_arena Boids.World.world_arena()
  @separation_radius_squared BoidFlockingConfig.boid_separation_radius() ** 2
  @boid_max_speed BoidFlockingConfig.boid_max_speed()
  @boid_min_speed BoidFlockingConfig.boid_min_speed()
  @boid_separation_weight BoidFlockingConfig.boid_separation_weight()

  @type t :: %__MODULE__{
          position: {float(), float()},
          velocity: {float(), float()}
        }

  @enforce_keys [:position, :velocity]
  defstruct [:position, :velocity]

  def new do
    %__MODULE__{position: random_position(), velocity: random_velocity()}
  end

  @spec advance_boid(Boids.Boid.t(), [Boids.Boid.t()]) :: Boids.Boid.t()
  def advance_boid(
        %__MODULE__{
          position: {current_x_pos, current_y_pos},
          velocity: {current_x_velocity, current_y_velocity}
        } = boid,
        neighbors
      ) do
    {separation_x, separation_y} = separation_steering_vector(boid, neighbors)
    separation_x_weighted = separation_x * @boid_separation_weight
    separation_y_weighted = separation_y * @boid_separation_weight

    cohesion_x_weighted = 0
    cohesion_y_weighted = 0

    alignment_x_weighted = 0
    alignment_y_weighted = 0

    steered_x_velocity = separation_x_weighted + cohesion_x_weighted + alignment_x_weighted
    steered_y_velocity = separation_y_weighted + cohesion_y_weighted + alignment_y_weighted

    composite_x_velocity = steered_x_velocity + current_x_velocity
    composite_y_velocity = steered_y_velocity + current_y_velocity

    {final_x_velocity, final_y_velocity} =
      limit_speed({composite_x_velocity, composite_y_velocity})

    new_x_pos = current_x_pos + final_x_velocity
    new_y_pos = current_y_pos + final_y_velocity

    {position, velocity} =
      clamp_to_arena({new_x_pos, new_y_pos}, {final_x_velocity, final_y_velocity})

    %__MODULE__{position: position, velocity: velocity}
  end

  defp separation_steering_vector(%__MODULE__{position: {x, y}}, neighbors) do
    neighbors
    |> Enum.map(fn %__MODULE__{position: {neighbor_x, neighbor_y}} ->
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

  defp clamp_to_arena({x, y}, {dx, dy}) do
    {x, dx} = clamp_axis(x, dx, @world_arena.left, @world_arena.left + @world_arena.width)
    {y, dy} = clamp_axis(y, dy, @world_arena.top, @world_arena.top + @world_arena.height)
    {{x, y}, {dx, dy}}
  end

  defp clamp_axis(pos, delta, min_boundary, _max_boundary) when pos < min_boundary,
    do: {min_boundary, -delta}

  defp clamp_axis(pos, delta, _min_boundary, max_boundary) when pos > max_boundary,
    do: {max_boundary, -delta}

  defp clamp_axis(pos, delta, _min_boundary, _max_boundary), do: {pos, delta}

  defp random_position do
    x = @world_arena.left + :rand.uniform() * @world_arena.width
    y = @world_arena.top + :rand.uniform() * @world_arena.height
    {x, y}
  end

  defp random_velocity do
    angle = :rand.uniform() * 2 * :math.pi()

    {BoidFlockingConfig.boid_initial_speed() * :math.cos(angle),
     BoidFlockingConfig.boid_initial_speed() * :math.sin(angle)}
  end

  # Take the current speed as a proportion of the max or min speeds, and scale each axis up or down accordingly.
  defp limit_speed({dx, dy}) do
    speed = :math.sqrt(dx * dx + dy * dy)

    cond do
      speed == 0 ->
        {dx, dy}

      speed > @boid_max_speed ->
        {dx * @boid_max_speed / speed, dy * @boid_max_speed / speed}

      speed < @boid_min_speed ->
        {dx * @boid_min_speed / speed, dy * @boid_min_speed / speed}

      true ->
        {dx, dy}
    end
  end
end
