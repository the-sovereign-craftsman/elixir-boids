defmodule Boids.BoidPositionsSupervisionTest do
  # Not async: these tests kill the app-wide positions table owner, and start and kill
  # real boids under the app's one DynamicSupervisor.
  use ExUnit.Case, async: false

  import Boids.AssertEventually
  import Boids.FlockTestHelpers
  import Mox

  alias Boids.BoidJanitor
  alias Boids.BoidPositions

  # The boids are started by the DynamicSupervisor, not this test process, so the mock
  # has to be global. stub_with/2 makes it behave like the real Boids.Boid.
  setup :set_mox_global

  setup do
    stub_with(Boids.BoidMock, Boids.Boid)
    on_exit(&Boids.remove_all_boids/0)
    :ok
  end

  test "killing the table owner restarts the janitor with it" do
    janitor_pid_before = Process.whereis(BoidJanitor)

    kill_owner_and_wait_for_restart()

    assert_eventually(fn ->
      janitor_pid = Process.whereis(BoidJanitor)
      is_pid(janitor_pid) and janitor_pid != janitor_pid_before
    end)
  end

  test "the boids and their supervisor survive the table owner dying" do
    spawn_watched_boids(3)
    boid_pids_before = running_boid_pids()
    boid_supervisor_pid_before = Process.whereis(Boids.DynamicSupervisor)

    kill_owner_and_wait_for_restart()

    assert Process.whereis(Boids.DynamicSupervisor) == boid_supervisor_pid_before
    assert Enum.sort(running_boid_pids()) == Enum.sort(boid_pids_before)
  end

  # A restarted janitor starts with no monitors. If it didn't adopt the boids that were
  # already running, killing one of them would leave its row behind and go uncounted.
  test "a restarted janitor watches the boids that were already running" do
    spawn_watched_boids(3)
    [boid_pid | _other_boid_pids] = boid_pids_before = running_boid_pids()

    kill_owner_and_wait_for_restart()
    crash_count_before = Boids.boid_crash_count()

    Process.exit(boid_pid, :kill)

    assert_eventually(fn -> Boids.boid_crash_count() == crash_count_before + 1 end)
    assert_killed_boids_replaced(boid_pids_before, 1)
  end

  test "the crash count survives the janitor being restarted" do
    spawn_watched_boids(2)
    [boid_pid | _other_boid_pids] = boid_pids_before = running_boid_pids()
    Process.exit(boid_pid, :kill)
    assert_killed_boids_replaced(boid_pids_before, 1)
    assert_eventually(fn -> Boids.boid_crash_count() > 0 end)
    crash_count_before = Boids.boid_crash_count()

    kill_owner_and_wait_for_restart()

    assert Boids.boid_crash_count() == crash_count_before
  end

  # Kills the owner, then waits until both processes in its group are back: a new owner
  # with a new table, and a new janitor that has finished starting up.
  defp kill_owner_and_wait_for_restart do
    owner_pid_before = Process.whereis(BoidPositions)
    janitor_pid_before = Process.whereis(BoidJanitor)

    Boids.kill_boid_positions_owner()

    assert_eventually(fn ->
      owner_pid = Process.whereis(BoidPositions)
      janitor_pid = Process.whereis(BoidJanitor)

      is_pid(owner_pid) and owner_pid != owner_pid_before and is_pid(janitor_pid) and
        janitor_pid != janitor_pid_before and
        :ets.info(BoidPositions.table_name()) != :undefined
    end)

    # A synchronous call, so the new janitor's init/1 (where it adopts the boids) is done.
    :sys.get_state(BoidJanitor)
  end
end
