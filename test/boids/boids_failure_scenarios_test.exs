defmodule Boids.BoidsFailureScenariosTest do
  # Not async: these tests start and kill real boids under the app's one
  # DynamicSupervisor, and read the app-wide crash count.
  use ExUnit.Case, async: false

  import Boids.AssertEventually
  import Boids.FlockTestHelpers
  import Mox

  alias Boids.BoidPositions

  # The boids are started by the DynamicSupervisor, not this test process, so the mock
  # has to be global. stub_with/2 makes it behave like the real Boids.Boid.
  setup :set_mox_global

  setup do
    stub_with(Boids.BoidMock, Boids.Boid)
    on_exit(&Boids.remove_all_boids/0)
    :ok
  end

  describe "kill_boids/1" do
    test "kills the requested number of boids and the supervisor restarts them" do
      Boids.spawn_boids(10)
      pids_before_kill = running_boid_pids()
      crash_count_before = Boids.boid_crash_count()

      assert Boids.kill_boids(4) == 4

      assert_killed_boids_replaced(pids_before_kill, 4)
      assert_eventually(fn -> Boids.boid_crash_count() == crash_count_before + 4 end)
      # Every killed boid's row is gone, and every restarted boid has written its own.
      assert_eventually(fn -> :ets.info(BoidPositions.table_name(), :size) == 10 end)
    end

    test "killing more boids than exist kills them all" do
      Boids.spawn_boids(3)
      pids_before_kill = running_boid_pids()
      crash_count_before = Boids.boid_crash_count()

      assert Boids.kill_boids(50) == 3

      assert_killed_boids_replaced(pids_before_kill, 3)
      assert_eventually(fn -> Boids.boid_crash_count() == crash_count_before + 3 end)
    end

    test "killing 0 boids kills nothing" do
      Boids.spawn_boids(2)

      assert Boids.kill_boids(0) == 0
      assert Boids.boid_count() == 2
    end

    # The default limit of 3 restarts in 5 seconds would make the supervisor give up and
    # stop every boid. The raised limit keeps it, and the whole flock, alive.
    test "survives more kills than the default restart limit allows" do
      Boids.spawn_boids(20)
      pids_before_kill = running_boid_pids()
      supervisor_pid = Process.whereis(Boids.DynamicSupervisor)

      Boids.kill_boids(20)

      assert_killed_boids_replaced(pids_before_kill, 20)
      assert Process.whereis(Boids.DynamicSupervisor) == supervisor_pid
    end
  end

  # Ticks are sent by hand in tests (tick_interval_ms is :manual), so each test ticks the
  # boids itself to make the corrupted ones run into their bad state. Each crash logs an
  # error report, which capture_log keeps out of the test output.
  describe "crash_boids/1" do
    @tag :capture_log
    test "corrupted boids crash on their next tick and the supervisor restarts them" do
      Boids.spawn_boids(10)
      pids_before_crash = running_boid_pids()
      crash_count_before = Boids.boid_crash_count()

      assert Boids.crash_boids(4) == 4
      tick_every_boid(pids_before_crash)

      assert_killed_boids_replaced(pids_before_crash, 4)
      assert_eventually(fn -> Boids.boid_crash_count() == crash_count_before + 4 end)
      assert_eventually(fn -> :ets.info(BoidPositions.table_name(), :size) == 10 end)
    end

    test "a corrupted boid keeps running until its next tick" do
      Boids.spawn_boids(1)
      [pid] = running_boid_pids()

      Boids.crash_boids(1)

      assert Process.alive?(pid)
      assert %Boids.Boid{velocity: :corrupted} = :sys.get_state(pid)
    end

    @tag :capture_log
    test "crashing more boids than exist crashes them all" do
      Boids.spawn_boids(3)
      pids_before_crash = running_boid_pids()

      assert Boids.crash_boids(50) == 3
      tick_every_boid(pids_before_crash)

      assert_killed_boids_replaced(pids_before_crash, 3)
    end
  end

  defp tick_every_boid(pids), do: Enum.each(pids, &send(&1, :tick))
end
