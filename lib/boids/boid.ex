defmodule Boids.Boid do
  @behaviour Boids.BoidBehaviour

  @initial_speed 10
  @world_width 1000.0
  @world_height 1000.0

  @world_arena %{top: 0.0, left: 0.0, width: @world_width, height: @world_height}

  @type t :: %__MODULE__{
          position: {float(), float()},
          velocity: {float(), float()}
        }

  @enforce_keys [:position, :velocity]
  defstruct [:position, :velocity]

  def new() do
    %__MODULE__{position: random_position(), velocity: random_velocity()}
  end

  def advance_boid(%__MODULE__{position: {x, y}, velocity: {dx, dy}}) do
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
