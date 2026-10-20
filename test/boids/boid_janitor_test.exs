defmodule Boids.BoidJanitorTest do
  # Not async: the janitor and its crash count are app-wide, so every test here
  # compares the count before and after rather than expecting an exact number.
  use ExUnit.Case, async: false

  import Boids.AssertEventually
  import Mox

  alias Boids.BoidJanitor
  alias Boids.BoidPositions
  alias Boids.BoidServer

  # The real-boid test starts a BoidServer under the test supervisor, not this test
  # process, so the mock has to be global.
  setup :set_mox_global

  describe "when a watched process dies" do
    test "deletes the row of a watched process that is killed" do
      pid = start_stand_in_boid()

      watch_and_wait_for_janitor(pid)
      Process.exit(pid, :kill)

      assert_eventually(fn -> rows_for(pid) == [] end)
    end

    test "counts a killed process as a crash" do
      crash_count_before = BoidJanitor.crash_count()
      pid = start_stand_in_boid()

      watch_and_wait_for_janitor(pid)
      Process.exit(pid, :kill)

      assert_eventually(fn -> BoidJanitor.crash_count() == crash_count_before + 1 end)
    end

    # A real boid that raises still runs terminate/2 (it traps exits), which deletes its
    # own row. So the janitor only counts it, and leaves the row alone. The stand-in has
    # no terminate/2, which is how the test can see that the janitor didn't touch it.
    # The raise is logged as an error report; capture_log keeps it out of the test output.
    @tag :capture_log
    test "counts a process that raises as a crash, and leaves its row to the process" do
      crash_count_before = BoidJanitor.crash_count()
      pid = start_stand_in_boid()

      watch_and_wait_for_janitor(pid)
      send(pid, :raise)

      assert_eventually(fn -> BoidJanitor.crash_count() == crash_count_before + 1 end)
      assert_janitor_handled_death(pid)
      assert rows_for(pid) != []
    end

    # Boids removed on purpose stop with :shutdown and delete their own rows. Scanning
    # the table for each one would make clearing 5,000 boids millions of row checks.
    test "does not count a process that stops with :shutdown, and leaves its row to the process" do
      crash_count_before = BoidJanitor.crash_count()
      pid = start_stand_in_boid()

      watch_and_wait_for_janitor(pid)
      Process.exit(pid, :shutdown)

      assert_janitor_handled_death(pid)
      assert BoidJanitor.crash_count() == crash_count_before
      assert rows_for(pid) != []
    end

    test "does not count a process that stops normally, and leaves its row to the process" do
      crash_count_before = BoidJanitor.crash_count()
      pid = start_stand_in_boid()

      watch_and_wait_for_janitor(pid)
      send(pid, :stop)

      assert_janitor_handled_death(pid)
      assert BoidJanitor.crash_count() == crash_count_before
      assert rows_for(pid) != []
    end

    # The boid registers with a cast, so it can die before the janitor monitors it.
    # The monitor then reports :noproc right away. The real exit reason is lost, so
    # the death isn't counted, but the row is still deleted.
    test "deletes rows but does not count a process that was already dead when watched" do
      crash_count_before = BoidJanitor.crash_count()
      pid = start_stand_in_boid()
      Process.exit(pid, :kill)

      watch_and_wait_for_janitor(pid)

      assert_eventually(fn -> rows_for(pid) == [] end)
      assert BoidJanitor.crash_count() == crash_count_before
    end
  end

  describe "with a real boid" do
    test "a real boid registers itself, and its killed row is cleaned up and counted" do
      stub_with(Boids.BoidMock, Boids.Boid)
      crash_count_before = BoidJanitor.crash_count()

      # :temporary, so the test supervisor doesn't restart it after the kill.
      pid = start_supervised!(Supervisor.child_spec({BoidServer, []}, restart: :temporary))
      # A synchronous call to the janitor, so the boid's registration cast is handled first.
      :sys.get_state(BoidJanitor)

      Process.exit(pid, :kill)

      assert_eventually(fn -> BoidJanitor.crash_count() == crash_count_before + 1 end)
      assert rows_for(pid) == []
    end
  end

  # A plain process with a boid-shaped row, standing in for a BoidServer. It stays
  # alive until it is killed, told to :stop (exits :normal), or told to :raise.
  defp start_stand_in_boid do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
          :raise -> raise "stand-in boid crashed"
        end
      end)

    :ets.insert(BoidPositions.table_name(), {{0, 0, pid}, :stand_in_boid})
    on_exit(fn -> :ets.match_delete(BoidPositions.table_name(), {{:_, :_, pid}, :_}) end)
    pid
  end

  # watch_boid/1 is a cast, so a process killed right after it can die before the janitor
  # monitors it (the :noproc case). A call from the same process is handled after the
  # cast, so once :sys.get_state/1 returns the janitor is watching.
  defp watch_and_wait_for_janitor(pid) do
    BoidJanitor.watch_boid(pid)
    :sys.get_state(BoidJanitor)
  end

  # The janitor drops a pid from the boids it watches once it has handled its :DOWN.
  defp assert_janitor_handled_death(pid) do
    assert_eventually(fn ->
      not MapSet.member?(:sys.get_state(BoidJanitor).watched_boid_pids, pid)
    end)
  end

  defp rows_for(pid) do
    :ets.match_object(BoidPositions.table_name(), {{:_, :_, pid}, :_})
  end
end
