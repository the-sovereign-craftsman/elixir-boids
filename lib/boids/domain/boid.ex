defmodule Boids.Boid do
  @moduledoc """
  Pure domain model of a single boid: its position and velocity, and how it
  moves one step.

  Contains no processes or state. `Boids.BoidServer` holds a `%Boid{}` and
  calls `advance_boid/2` on every tick. Boids that reach the edge of the
  `Boids.World` arena are clamped to the wall and bounce back.
  """

  @behaviour Boids.BoidBehaviour

  @initial_speed 2
  @world_arena Boids.World.world_arena()

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
        %__MODULE__{position: {x, y}, velocity: {dx, dy}},
        neighbors
      ) do
    new_x_pos = x + dx
    new_y_pos = y + dy

    {position, velocity} = clamp_to_arena({new_x_pos, new_y_pos}, {dx, dy})
    %__MODULE__{position: position, velocity: velocity}
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
    {@initial_speed * :math.cos(angle), @initial_speed * :math.sin(angle)}
  end
end
