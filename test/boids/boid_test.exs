defmodule Boids.BoidTest do
  use ExUnit.Case, async: true

  alias Boids.Boid

  describe "new/0" do
    test "returns a boid with position inside the world bounds and velocity at the expected speed" do
      %Boid{position: {x, y}, velocity: {dx, dy}} = Boid.new()

      assert x >= 0 and x < 1000
      assert y >= 0 and y < 1000
      assert_in_delta :math.sqrt(dx * dx + dy * dy), 2, 0.0001
    end
  end

  describe "advance_boid/2" do
    test "advances position by velocity when the result stays within bounds" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {5.0, 5.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {15.0, 15.0}, velocity: {5.0, 5.0}}
    end

    test "clamps position and reverses velocity when crossing the right boundary" do
      boid = %Boid{position: {999.0, 500.0}, velocity: {5.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{
               position: {1000.0, 500.0},
               velocity: {-5.0, 0.0}
             }
    end

    test "clamps position and reverses velocity when crossing the left boundary" do
      boid = %Boid{position: {1.0, 500.0}, velocity: {-5.0, 0.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {0.0, 500.0}, velocity: {5.0, 0.0}}
    end

    test "clamps position and reverses velocity when crossing the top boundary" do
      boid = %Boid{position: {500.0, 1.0}, velocity: {0.0, -5.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {500.0, 0.0}, velocity: {0.0, 5.0}}
    end

    test "clamps position and reverses velocity when crossing the bottom boundary" do
      boid = %Boid{position: {500.0, 999.0}, velocity: {0.0, 5.0}}

      assert Boid.advance_boid(boid, []) == %Boid{
               position: {500.0, 1000.0},
               velocity: {0.0, -5.0}
             }
    end

    test "clamps both axes independently when both cross a boundary in the same tick" do
      boid = %Boid{position: {1.0, 1.0}, velocity: {-5.0, -5.0}}

      assert Boid.advance_boid(boid, []) == %Boid{position: {0.0, 0.0}, velocity: {5.0, 5.0}}
    end

    test "accepts any number of neighbors, including ones unlike the boid itself" do
      boid = %Boid{position: {10.0, 10.0}, velocity: {5.0, 5.0}}

      neighbors = [
        %Boid{position: {20.0, 20.0}, velocity: {1.0, 0.0}},
        %Boid{position: {30.0, 15.0}, velocity: {0.0, -1.0}}
      ]

      assert %Boid{} = Boid.advance_boid(boid, [])
      assert %Boid{} = Boid.advance_boid(boid, Enum.take(neighbors, 1))
      assert %Boid{} = Boid.advance_boid(boid, neighbors)
    end
  end
end
