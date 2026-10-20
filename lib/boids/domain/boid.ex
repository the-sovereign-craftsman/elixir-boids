defmodule Boids.Boid do
  @moduledoc """
  Pure domain model of a single boid: its position and velocity, and how it
  moves one step.

  Contains no processes or state. `Boids.BoidServer` holds a `%Boid{}` and
  calls `advance_boid/3` on every tick. Boids that reach the edge of the
  `Boids.World` arena are clamped to the wall and bounce back.
  """

  @behaviour Boids.BoidBehaviour

  alias Boids.BoidFlockingConfig
  alias Boids.BoidFlockingRules
  alias Boids.BoidFlockingRuleToggles

  @world_arena Boids.World.world_arena()
  @boid_max_speed BoidFlockingConfig.boid_max_speed()
  @boid_min_speed BoidFlockingConfig.boid_min_speed()

  # spawned_at_ms is when new/0 made the boid, in System.monotonic_time(:millisecond).
  # A boid restarted by its supervisor is a new boid with a new spawn time, which is
  # how the canvas highlights the boids that replaced killed ones. nil for boids built
  # by hand, as in tests.
  @type t :: %__MODULE__{
          position: {float(), float()},
          velocity: {float(), float()},
          spawned_at_ms: integer() | nil
        }

  @enforce_keys [:position, :velocity]
  defstruct [:position, :velocity, spawned_at_ms: nil]

  def new do
    %__MODULE__{
      position: random_position(),
      velocity: random_velocity(),
      spawned_at_ms: System.monotonic_time(:millisecond)
    }
  end

  @spec advance_boid(t(), [t()], BoidFlockingRuleToggles.enabled_flocking_rules()) :: t()
  def advance_boid(
        %__MODULE__{
          position: {current_x_pos, current_y_pos},
          velocity: {current_x_velocity, current_y_velocity}
        } = boid,
        neighbors,
        flocking_rule_toggles
      ) do
    {steering_x, steering_y} =
      BoidFlockingRules.combined_steering_vector(boid, neighbors, flocking_rule_toggles)

    composite_x_velocity = current_x_velocity + steering_x
    composite_y_velocity = current_y_velocity + steering_y

    {final_x_velocity, final_y_velocity} =
      limit_speed({composite_x_velocity, composite_y_velocity})

    new_x_pos = current_x_pos + final_x_velocity
    new_y_pos = current_y_pos + final_y_velocity

    {position, velocity} =
      clamp_to_arena({new_x_pos, new_y_pos}, {final_x_velocity, final_y_velocity})

    # Updates the boid rather than building a new one, so its spawn time carries over.
    %__MODULE__{boid | position: position, velocity: velocity}
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
