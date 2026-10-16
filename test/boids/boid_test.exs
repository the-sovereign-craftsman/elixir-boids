defmodule Boids.BoidTest do
  use ExUnit.Case, async: true

  alias Boids.Boid
  alias Boids.BoidFlockingConfig

  @max_speed BoidFlockingConfig.boid_max_speed()
  @min_speed BoidFlockingConfig.boid_min_speed()

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
  describe "advance_boid/2 movement and arena bounds" do
    test "advances position by velocity when the result stays within bounds" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {2.0, 2.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {12.0, 12.0}, velocity: {2.0, 2.0}}
    end

    test "clamps position and reverses velocity when crossing the right boundary" do
      boid = %Boid{position: {999.0, 500.0}, velocity: {3.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{
               position: {1000.0, 500.0},
               velocity: {-3.0, 0.0}
             }
    end

    test "clamps position and reverses velocity when crossing the left boundary" do
      boid = %Boid{position: {1.0, 500.0}, velocity: {-3.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {0.0, 500.0}, velocity: {3.0, 0.0}}
    end

    test "clamps position and reverses velocity when crossing the top boundary" do
      boid = %Boid{position: {500.0, 1.0}, velocity: {0.0, -3.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {500.0, 0.0}, velocity: {0.0, 3.0}}
    end

    test "clamps position and reverses velocity when crossing the bottom boundary" do
      boid = %Boid{position: {500.0, 999.0}, velocity: {0.0, 3.0}}

      assert Boid.advance_boid(boid, []) == %Boid{
               position: {500.0, 1000.0},
               velocity: {0.0, -3.0}
             }
    end

    test "clamps both axes independently when both cross a boundary in the same tick" do
      boid = %Boid{position: {1.0, 1.0}, velocity: {-2.0, -2.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {0.0, 0.0}, velocity: {2.0, 2.0}}
    end

    test "accepts any number of neighbors, including ones unlike the boid itself" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {2.0, 2.0}}

      neighbors = [
        %Boid{position: {20.0, 20.0}, velocity: {1.0, 0.0}},
        %Boid{position: {30.0, 15.0}, velocity: {0.0, -1.0}}
      ]

      assert %Boid{} = Boid.advance_boid(boid, [])
      assert %Boid{} = Boid.advance_boid(boid, Enum.take(neighbors, 1))
      assert %Boid{} = Boid.advance_boid(boid, neighbors)
    end
  end

  describe "advance_boid/2 speed limit" do
    test "slows a boid that is faster than the max speed down to the max speed" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {5.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {504.0, 500.0}, velocity: {4.0, 0.0}}
    end

    test "speeds up a boid that is slower than the min speed to the min speed" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {1.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {502.0, 500.0}, velocity: {2.0, 0.0}}
    end

    test "keeps the boid's direction when it changes its speed" do
      # {5, 5} has a speed of ~7.07, heading exactly diagonal.
      boid = %Boid{position: {500.0, 500.0}, velocity: {5.0, 5.0}}

      %Boid{velocity: {dx, dy} = velocity} = Boid.advance_boid(boid, [])

      assert_in_delta speed_of(velocity), @max_speed, 0.0001
      assert_in_delta dx, dy, 0.0001
    end

    test "leaves a stationary boid stationary instead of dividing by zero" do
      boid = %Boid{position: {500.0, 500.0}, velocity: {0.0, 0.0}}

      assert Boid.advance_boid(boid, []) == boid
    end
  end

  # Every boid in this block sits at {500, 500} moving straight up at speed 3, so any
  # sideways (x) velocity afterwards comes from separation. With a separation weight of
  # 10, a neighbor at distance d directly to one side pushes with strength 10 / d.
  describe "advance_boid/2 separation" do
    @boid_moving_up %Boid{position: {500.0, 500.0}, velocity: {0.0, -3.0}}

    test "with no neighbors, the boid keeps its velocity" do
      assert Boid.advance_boid(@boid_moving_up, []).velocity == {0.0, -3.0}
    end

    test "a neighbor to the left pushes the boid to the right" do
      neighbor_to_the_left = neighbor_at({490.0, 500.0})

      %Boid{position: {x, y}, velocity: {dx, dy}} =
        Boid.advance_boid(@boid_moving_up, [neighbor_to_the_left])

      # Distance 10 -> push of 10 / 10 = 1 to the right.
      assert_in_delta dx, 1.0, 0.0001
      assert_in_delta dy, -3.0, 0.0001
      assert_in_delta x, 501.0, 0.0001
      assert_in_delta y, 497.0, 0.0001
    end

    test "a neighbor to the right pushes the boid to the left" do
      %Boid{velocity: {dx, _dy}} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({510.0, 500.0})])

      assert_in_delta dx, -1.0, 0.0001
    end

    test "a closer neighbor pushes harder than a farther one" do
      %Boid{velocity: {push_from_distance_10, _dy}} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({490.0, 500.0})])

      %Boid{velocity: {push_from_distance_5, _dy}} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({495.0, 500.0})])

      assert_in_delta push_from_distance_10, 1.0, 0.0001
      assert_in_delta push_from_distance_5, 2.0, 0.0001
    end

    test "a neighbor exactly on the separation radius still pushes" do
      # Distance 20 -> push of 10 / 20 = 0.5.
      %Boid{velocity: {dx, _dy}} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({480.0, 500.0})])

      assert_in_delta dx, 0.5, 0.0001
    end

    test "a neighbor beyond the separation radius is ignored" do
      # Distance 30: inside the perception radius, so it is a neighbor, but too far to repel.
      assert Boid.advance_boid(@boid_moving_up, [neighbor_at({470.0, 500.0})]).velocity ==
               {0.0, -3.0}
    end

    test "a neighbor at exactly the same position is ignored instead of dividing by zero" do
      assert Boid.advance_boid(@boid_moving_up, [neighbor_at({500.0, 500.0})]).velocity ==
               {0.0, -3.0}
    end

    test "equal neighbors on opposite sides cancel out" do
      neighbors = [neighbor_at({490.0, 500.0}), neighbor_at({510.0, 500.0})]

      %Boid{velocity: {dx, dy}} = Boid.advance_boid(@boid_moving_up, neighbors)

      assert_in_delta dx, 0.0, 0.0001
      assert_in_delta dy, -3.0, 0.0001
    end

    test "pushes from several neighbors add together" do
      # Both are 10 to the left, one slightly above and one slightly below. Their vertical
      # pushes cancel and their sideways pushes add: 2 x (10 x 10 / 125) = 1.6.
      neighbors = [neighbor_at({490.0, 495.0}), neighbor_at({490.0, 505.0})]

      %Boid{velocity: {dx, dy}} = Boid.advance_boid(@boid_moving_up, neighbors)

      assert_in_delta dx, 1.6, 0.0001
      assert_in_delta dy, -3.0, 0.0001
    end

    test "a very strong push is still capped at the max speed" do
      # Distance 1 -> push of 10, far more than the max speed.
      %Boid{velocity: velocity} =
        Boid.advance_boid(@boid_moving_up, [neighbor_at({499.0, 500.0})])

      assert_in_delta speed_of(velocity), @max_speed, 0.0001
    end

    test "the neighbor's velocity does not affect separation" do
      %Boid{velocity: velocity_beside_still_neighbor} =
        Boid.advance_boid(@boid_moving_up, [
          %Boid{position: {490.0, 500.0}, velocity: {0.0, 0.0}}
        ])

      %Boid{velocity: velocity_beside_fast_neighbor} =
        Boid.advance_boid(@boid_moving_up, [
          %Boid{position: {490.0, 500.0}, velocity: {4.0, 4.0}}
        ])

      assert velocity_beside_still_neighbor == velocity_beside_fast_neighbor
    end
  end

  defp neighbor_at(position), do: %Boid{position: position, velocity: {@min_speed, 0.0}}

  defp speed_of({dx, dy}), do: :math.sqrt(dx * dx + dy * dy)
end
