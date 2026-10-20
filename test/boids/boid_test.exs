defmodule Boids.BoidTest do
  use ExUnit.Case, async: true

  alias Boids.Boid
  alias Boids.BoidFlockingConfig
  alias Boids.BoidFlockingRules

  @max_speed BoidFlockingConfig.boid_max_speed()
  @min_speed BoidFlockingConfig.boid_min_speed()

  @all_rules_on %{separation: true, cohesion: true, alignment: true}
  @all_rules_off %{separation: false, cohesion: false, alignment: false}

  describe "new/0" do
    test "returns a boid with position inside the world bounds and velocity at the expected speed" do
      %Boid{position: {x, y}, velocity: velocity} = Boid.new()

      assert x >= 0 and x < 1000
      assert y >= 0 and y < 1000
      assert_in_delta speed_of(velocity), BoidFlockingConfig.boid_initial_speed(), 0.0001
    end
  end

  # Velocities in this block have speeds between the min (2) and max (4) speed, so the
  # speed limit leaves them alone and each test only checks movement and bouncing.
  describe "advance_boid/3 movement and arena bounds" do
    test "advances position by velocity when the result stays within bounds" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {2.0, 2.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {12.0, 12.0},
               velocity: {2.0, 2.0}
             }
    end

    test "clamps position and reverses velocity when crossing the right boundary" do
      boid = %Boid{position: {999.0, 500.0}, velocity: {3.0, 0.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {1000.0, 500.0},
               velocity: {-3.0, 0.0}
             }
    end

    test "clamps position and reverses velocity when crossing the left boundary" do
      boid = %Boid{position: {1.0, 500.0}, velocity: {-3.0, 0.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {0.0, 500.0},
               velocity: {3.0, 0.0}
             }
    end

    test "clamps position and reverses velocity when crossing the top boundary" do
      boid = %Boid{position: {500.0, 1.0}, velocity: {0.0, -3.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {500.0, 0.0},
               velocity: {0.0, 3.0}
             }
    end

    test "clamps position and reverses velocity when crossing the bottom boundary" do
      boid = %Boid{position: {500.0, 999.0}, velocity: {0.0, 3.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {500.0, 1000.0},
               velocity: {0.0, -3.0}
             }
    end

    test "clamps both axes independently when both cross a boundary in the same tick" do
      boid = %Boid{position: {1.0, 1.0}, velocity: {-2.0, -2.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {0.0, 0.0},
               velocity: {2.0, 2.0}
             }
    end

    test "accepts any number of neighbors, including ones unlike the boid itself" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {2.0, 2.0}}

      neighbors = [
        %Boid{position: {20.0, 20.0}, velocity: {1.0, 0.0}},
        %Boid{position: {30.0, 15.0}, velocity: {0.0, -1.0}}
      ]

      assert %Boid{} = Boid.advance_boid(boid, [], @all_rules_on)
      assert %Boid{} = Boid.advance_boid(boid, Enum.take(neighbors, 1), @all_rules_on)
      assert %Boid{} = Boid.advance_boid(boid, neighbors, @all_rules_on)
    end
  end

  describe "advance_boid/3 speed limit" do
    test "slows a boid that is faster than the max speed down to the max speed" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {5.0, 0.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {504.0, 500.0},
               velocity: {4.0, 0.0}
             }
    end

    test "speeds up a boid that is slower than the min speed to the min speed" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {1.0, 0.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == %Boid{
               position: {502.0, 500.0},
               velocity: {2.0, 0.0}
             }
    end

    test "keeps the boid's direction when it changes its speed" do
      # {5, 5} has a speed of ~7.07, heading exactly diagonal.
      boid = %Boid{position: {500.0, 500.0}, velocity: {5.0, 5.0}}

      %Boid{velocity: {dx, dy} = velocity} = Boid.advance_boid(boid, [], @all_rules_on)

      assert_in_delta speed_of(velocity), @max_speed, 0.0001
      assert_in_delta dx, dy, 0.0001
    end

    test "leaves a stationary boid stationary instead of dividing by zero" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {0.0, 0.0}}

      assert Boid.advance_boid(boid, [], @all_rules_on) == boid
    end
  end

  # Which way to steer is decided by Boids.BoidFlockingRules.combined_steering_vector/4,
  # tested in boid_flocking_rules_test.exs. These tests only check that advance_boid/3
  # applies that steering: adds it to the velocity, limits the speed, then moves.
  describe "advance_boid/3 applying the steering" do
    @boid_moving_up %Boid{position: {500.0, 500.0}, velocity: {0.0, -3.0}}

    test "with no neighbors, there is no steering and the boid keeps its velocity" do
      assert Boid.advance_boid(@boid_moving_up, [], @all_rules_on) == %Boid{
               position: {500.0, 497.0},
               velocity: {0.0, -3.0}
             }
    end

    test "adds the combined steering vector to the velocity" do
      neighbors = [neighbor_at({490.0, 500.0})]

      {steering_x, steering_y} =
        BoidFlockingRules.combined_steering_vector(@boid_moving_up, neighbors, @all_rules_on)

      %Boid{velocity: {dx, dy}} = Boid.advance_boid(@boid_moving_up, neighbors, @all_rules_on)

      assert_in_delta dx, 0.0 + steering_x, 0.0001
      assert_in_delta dy, -3.0 + steering_y, 0.0001
    end

    test "moves by the new, steered velocity in the same tick" do
      neighbors = [neighbor_at({490.0, 500.0})]

      %Boid{position: {x, y}, velocity: {dx, dy}} =
        Boid.advance_boid(@boid_moving_up, neighbors, @all_rules_on)

      assert_in_delta x, 500.0 + dx, 0.0001
      assert_in_delta y, 500.0 + dy, 0.0001
    end

    test "a very strong steer is still capped at the max speed" do
      # Distance 1: a separation push far larger than the max speed.
      %Boid{velocity: velocity} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({499.0, 500.0})], @all_rules_on)

      assert_in_delta speed_of(velocity), @max_speed, 0.0001
    end

    test "with every rule turned off, neighbors don't change the boid's velocity" do
      neighbors = [neighbor_at({490.0, 500.0}), neighbor_at({470.0, 520.0})]

      assert Boid.advance_boid(@boid_moving_up, neighbors, @all_rules_off) ==
               Boid.advance_boid(@boid_moving_up, [], @all_rules_off)
    end

    test "passes the rule toggles through to the combined steering" do
      neighbors = [neighbor_at({490.0, 500.0})]
      cohesion_only = %{@all_rules_off | cohesion: true}

      {steering_x, steering_y} =
        BoidFlockingRules.combined_steering_vector(@boid_moving_up, neighbors, cohesion_only)

      %Boid{velocity: {dx, dy}} = Boid.advance_boid(@boid_moving_up, neighbors, cohesion_only)

      assert_in_delta dx, 0.0 + steering_x, 0.0001
      assert_in_delta dy, -3.0 + steering_y, 0.0001
    end
  end

  defp neighbor_at(position), do: %Boid{position: position, velocity: {@min_speed, 0.0}}

  defp speed_of({dx, dy}), do: :math.sqrt(dx * dx + dy * dy)
end
