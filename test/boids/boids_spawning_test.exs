defmodule Boids.BoidsSpawningTest do
  # Not async: these tests start real boids under the app's one DynamicSupervisor and
  # count them, so they can't share it with other tests.
  use ExUnit.Case, async: false

  import Mox

  alias Boids.BoidPositions

  # The boids are started by the DynamicSupervisor, not this test process, so the mock
  # has to be global. stub_with/2 makes it behave like the real Boids.Boid.
  setup :set_mox_global

  setup do
    stub_with(Boids.BoidMock, Boids.Boid)
    on_exit(&stop_all_boids/0)
    :ok
  end

  describe "spawn_boids/1" do
    test "spawns the requested number of boids" do
      assert length(Boids.spawn_boids(3)) == 3
      assert Boids.boid_count() == 3
    end

    test "spawns nothing for a count of 0" do
      assert Boids.spawn_boids(0) == []
      assert Boids.boid_count() == 0
    end
  end

  describe "boid_count/0" do
    test "counts the boid processes that are alive" do
      assert Boids.boid_count() == 0

      Boids.spawn_boids(4)

      assert Boids.boid_count() == 4
    end
  end

  describe "set_boid_count/1" do
    test "spawns boids up to the target and returns the new count" do
      Boids.spawn_boids(2)

      assert Boids.set_boid_count(10) == 10
      assert Boids.boid_count() == 10
    end

    test "removes boids down to the target and returns the new count" do
      Boids.spawn_boids(10)

      assert Boids.set_boid_count(4) == 4
      assert Boids.boid_count() == 4
    end

    test "does nothing when the count already matches" do
      pids = Boids.spawn_boids(5)

      assert Boids.set_boid_count(5) == 5
      assert Enum.all?(pids, &Process.alive?/1)
    end

    test "can take the flock down to 0" do
      Boids.spawn_boids(6)

      assert Boids.set_boid_count(0) == 0
      assert Boids.boid_count() == 0
    end

    test "caps the target at the limit" do
      assert Boids.set_boid_count(Boids.max_boid_count() + 100) == Boids.max_boid_count()
    end

    test "brings a flock over the limit, as from iex, down to the limit" do
      Boids.spawn_boids(Boids.max_boid_count() + 3)

      assert Boids.set_boid_count(Boids.max_boid_count() + 50) == Boids.max_boid_count()
    end
  end

  describe "remove_boids/1" do
    test "stops the requested number of boids" do
      Boids.spawn_boids(5)

      assert Boids.remove_boids(2) == :ok
      assert Boids.boid_count() == 3
    end

    test "removing more boids than exist stops them all" do
      Boids.spawn_boids(3)

      Boids.remove_boids(10)

      assert Boids.boid_count() == 0
    end

    test "removed boids leave no rows behind, so nothing stays frozen on the canvas" do
      pids = Boids.spawn_boids(4)

      Boids.remove_boids(4)

      for pid <- pids do
        assert rows_for(pid) == []
      end
    end
  end

  describe "remove_all_boids/0" do
    test "stops every boid and removes every row" do
      pids = Boids.spawn_boids(8)

      assert Boids.remove_all_boids() == :ok
      assert Boids.boid_count() == 0
      assert Enum.flat_map(pids, &rows_for/1) == []
    end
  end

  defp rows_for(pid), do: :ets.match_object(BoidPositions.table_name(), {{:_, :_, pid}, :_})

  defp stop_all_boids, do: Boids.remove_all_boids()
end
