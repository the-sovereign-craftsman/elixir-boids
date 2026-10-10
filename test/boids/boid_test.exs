defmodule Boids.BoidTest do
  use ExUnit.Case, async: true

  alias Boids.Boid

  describe "init/1" do
    test "starts with a random position inside the world bounds and velocity at the expected speed" do
      pid = start_supervised!({Boid, []})

      %Boid{position: {x, y}, velocity: {dx, dy}} = :sys.get_state(pid)

      assert x >= 0 and x < 1000
      assert y >= 0 and y < 1000
      assert_in_delta :math.sqrt(dx * dx + dy * dy), 2, 0.0001
    end
  end

  describe "handle_info/2" do
    test "advances position by velocity when the result stays within bounds" do
      pid = start_supervised!({Boid, []})
      :sys.replace_state(pid, fn _ -> %Boid{position: {10.0, 10.0}, velocity: {5.0, 5.0}} end)

      send(pid, :tick)

      assert :sys.get_state(pid) == %Boid{position: {15.0, 15.0}, velocity: {5.0, 5.0}}
    end

    test "clamps position and reverses velocity when crossing the right/bottom boundary" do
      pid = start_supervised!({Boid, []})
      :sys.replace_state(pid, fn _ -> %Boid{position: {999.0, 500.0}, velocity: {5.0, 0.0}} end)

      send(pid, :tick)

      assert :sys.get_state(pid) == %Boid{position: {1000.0, 500.0}, velocity: {-5.0, 0.0}}
    end

    test "clamps position and reverses velocity when crossing the left/top boundary" do
      pid = start_supervised!({Boid, []})
      :sys.replace_state(pid, fn _ -> %Boid{position: {1.0, 1.0}, velocity: {-5.0, -5.0}} end)

      send(pid, :tick)

      assert :sys.get_state(pid) == %Boid{position: {0.0, 0.0}, velocity: {5.0, 5.0}}
    end
  end
end
