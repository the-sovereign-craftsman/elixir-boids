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

  describe "spawn_boids_up_to_limit/1" do
    test "spawns the requested number when there is room, and returns it" do
      assert Boids.spawn_boids_up_to_limit(10) == 10
      assert Boids.boid_count() == 10
    end

    test "stops at the limit and returns how many it actually spawned" do
      Boids.spawn_boids(Boids.max_boid_count() - 5)

      assert Boids.spawn_boids_up_to_limit(20) == 5
      assert Boids.boid_count() == Boids.max_boid_count()
    end

    test "spawns nothing once the limit is reached" do
      Boids.spawn_boids(Boids.max_boid_count())

      assert Boids.spawn_boids_up_to_limit(1) == 0
      assert Boids.boid_count() == Boids.max_boid_count()
    end

    test "spawns nothing when there are already more boids than the limit, as from iex" do
      Boids.spawn_boids(Boids.max_boid_count() + 2)

      assert Boids.spawn_boids_up_to_limit(1) == 0
      assert Boids.boid_count() == Boids.max_boid_count() + 2
    end
  end

  # Stops every boid and removes its row; rows aren't cleaned up on their own yet.
  defp stop_all_boids do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Boids.DynamicSupervisor) do
      DynamicSupervisor.terminate_child(Boids.DynamicSupervisor, pid)
      :ets.match_delete(BoidPositions.table_name(), {{:_, :_, pid}, :_})
    end
  end
end
