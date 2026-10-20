defmodule Boids.BoidServerTest do
  use ExUnit.Case, async: true

  import Mox

  alias Boids.Boid
  alias Boids.BoidFlockingRuleToggles
  alias Boids.BoidMock
  alias Boids.BoidPositions
  alias Boids.BoidServer
  alias Boids.BoidSpatialGrid
  alias Boids.SimulationMetrics

  setup :verify_on_exit!

  # BoidServer resolves its boid module from Application.get_env(:boids, :boid_module),
  # which config/test.exs sets to BoidMock (defined in test/test_helper.exs).

  describe "init/1" do
    test "delegates to the configured boid_module to build the initial state" do
      initial_boid = %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
      expect(BoidMock, :new, fn -> initial_boid end)

      pid = start_supervised!({BoidServer, []})

      assert :sys.get_state(pid) == initial_boid
    end

    test "writes the initial boid to the positions table keyed by its pid" do
      initial_boid = %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
      expect(BoidMock, :new, fn -> initial_boid end)

      pid = start_supervised!({BoidServer, []})

      {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(initial_boid.position)

      assert :ets.lookup(BoidPositions.table_name(), {cell_x, cell_y, pid}) == [
               {{cell_x, cell_y, pid}, initial_boid}
             ]
    end
  end

  describe "handle_info/2" do
    test "delegates to the configured boid_module to advance state on :tick" do
      initial_boid = %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
      advanced_boid = %Boid{position: {1.0, 1.0}, velocity: {1.0, 1.0}}

      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, _flocking_rule_toggles ->
        advanced_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      assert :sys.get_state(pid) == advanced_boid
    end

    test "overwrites its row in the positions table on :tick" do
      initial_boid = %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
      advanced_boid = %Boid{position: {1.0, 1.0}, velocity: {1.0, 1.0}}

      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, _flocking_rule_toggles ->
        advanced_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      # get_state is a synchronous call, so once it returns the :tick has been handled.
      :sys.get_state(pid)

      {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(advanced_boid.position)

      assert :ets.lookup(BoidPositions.table_name(), {cell_x, cell_y, pid}) == [
               {{cell_x, cell_y, pid}, advanced_boid}
             ]
    end

    test "keeps a single row when the boid stays in the same cell" do
      # {10.0, 10.0} and {20.0, 10.0} are both in cell {0, 0}.
      initial_boid = %Boid{position: {10.0, 10.0}, velocity: {10.0, 0.0}}
      advanced_boid = %Boid{position: {20.0, 10.0}, velocity: {10.0, 0.0}}

      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, _flocking_rule_toggles ->
        advanced_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)
      :sys.get_state(pid)

      assert rows_for(pid) == [{{0, 0, pid}, advanced_boid}]
    end

    test "moves its row to the new cell key and deletes the old one when crossing a cell boundary" do
      # {40.0, 10.0} is in cell {0, 0}; {60.0, 10.0} is in cell {1, 0}.
      initial_boid = %Boid{position: {40.0, 10.0}, velocity: {20.0, 0.0}}
      advanced_boid = %Boid{position: {60.0, 10.0}, velocity: {20.0, 0.0}}

      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, _flocking_rule_toggles ->
        advanced_boid
      end)

      pid = start_supervised!({BoidServer, []})
      assert rows_for(pid) == [{{0, 0, pid}, initial_boid}]

      send(pid, :tick)
      :sys.get_state(pid)

      assert :ets.lookup(BoidPositions.table_name(), {0, 0, pid}) == []
      assert rows_for(pid) == [{{1, 0, pid}, advanced_boid}]
    end

    test "leaves no stale rows behind across several cell changes" do
      # Cells {0, 0} -> {1, 0} -> {1, 1} -> {0, 1}, one cell change per tick.
      boid_0 = %Boid{position: {40.0, 40.0}, velocity: {0.0, 0.0}}
      boid_1 = %Boid{position: {60.0, 40.0}, velocity: {0.0, 0.0}}
      boid_2 = %Boid{position: {60.0, 60.0}, velocity: {0.0, 0.0}}
      boid_3 = %Boid{position: {40.0, 60.0}, velocity: {0.0, 0.0}}

      expect(BoidMock, :new, fn -> boid_0 end)

      expect(BoidMock, :advance_boid, fn ^boid_0, _neighbors, _flocking_rule_toggles -> boid_1 end)

      expect(BoidMock, :advance_boid, fn ^boid_1, _neighbors, _flocking_rule_toggles -> boid_2 end)

      expect(BoidMock, :advance_boid, fn ^boid_2, _neighbors, _flocking_rule_toggles -> boid_3 end)

      pid = start_supervised!({BoidServer, []})

      for _ <- 1..3, do: send(pid, :tick)
      :sys.get_state(pid)

      assert rows_for(pid) == [{{0, 1, pid}, boid_3}]
    end

    test "boids in the same cell keep separate rows" do
      boid_a = %Boid{position: {10.0, 10.0}, velocity: {0.0, 0.0}}
      boid_b = %Boid{position: {20.0, 20.0}, velocity: {0.0, 0.0}}

      expect(BoidMock, :new, fn -> boid_a end)
      expect(BoidMock, :new, fn -> boid_b end)

      pid_a = start_supervised!({BoidServer, []}, id: :boid_a)
      pid_b = start_supervised!({BoidServer, []}, id: :boid_b)

      # Both are in cell {0, 0}; the pid in the key stops one overwriting the other.
      assert rows_for(pid_a) == [{{0, 0, pid_a}, boid_a}]
      assert rows_for(pid_b) == [{{0, 0, pid_b}, boid_b}]
    end
  end

  describe "terminate/2" do
    test "deletes the boid's row when it is stopped" do
      initial_boid = %Boid{position: {10.0, 10.0}, velocity: {0.0, 0.0}}
      expect(BoidMock, :new, fn -> initial_boid end)

      pid = start_supervised!({BoidServer, []})
      assert rows_for(pid) == [{{0, 0, pid}, initial_boid}]

      # Stops it the way a supervisor does, with a :shutdown exit signal.
      :ok = stop_supervised(BoidServer)

      assert rows_for(pid) == []
    end

    test "deletes the row from the cell the boid has moved to" do
      # {40.0, 10.0} is in cell {0, 0}; {60.0, 10.0} is in cell {1, 0}.
      initial_boid = %Boid{position: {40.0, 10.0}, velocity: {20.0, 0.0}}
      advanced_boid = %Boid{position: {60.0, 10.0}, velocity: {20.0, 0.0}}

      expect(BoidMock, :new, fn -> initial_boid end)
      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, _toggles -> advanced_boid end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)
      :sys.get_state(pid)

      :ok = stop_supervised(BoidServer)

      assert rows_for(pid) == []
    end

    test "deletes the row when the boid crashes" do
      initial_boid = %Boid{position: {10.0, 10.0}, velocity: {0.0, 0.0}}
      expect(BoidMock, :new, fn -> initial_boid end)
      expect(BoidMock, :advance_boid, fn _boid, _neighbors, _toggles -> raise "boom" end)

      pid = start_supervised!({BoidServer, []}, restart: :temporary)
      monitor_ref = Process.monitor(pid)

      ExUnit.CaptureLog.capture_log(fn ->
        send(pid, :tick)
        assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}
      end)

      assert rows_for(pid) == []
    end
  end

  describe "handle_info/2 neighbor lookup" do
    # These tests use their own regions of the world (x ~725-925, y ~825-975) so
    # rows from other async tests sharing the table can't land in their searches.

    test "passes the boids within its perception radius to advance_boid, excluding itself and far boids" do
      initial_boid = %Boid{position: {725.0, 825.0}, velocity: {0.0, 0.0}}
      near_boid = insert_boid_row({735.0, 825.0})
      _far_boid = insert_boid_row({725.0, 975.0})

      test_pid = self()
      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, neighbors, _flocking_rule_toggles ->
        send(test_pid, {:neighbors_passed_to_advance_boid, neighbors})
        initial_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      # The server's own row is at the center of the search, so this also proves it excludes itself.
      assert_receive {:neighbors_passed_to_advance_boid, neighbors}
      assert neighbors == [near_boid]
    end

    test "passes an empty list when no other boid is within its perception radius" do
      initial_boid = %Boid{position: {925.0, 825.0}, velocity: {0.0, 0.0}}

      test_pid = self()
      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, neighbors, _flocking_rule_toggles ->
        send(test_pid, {:neighbors_passed_to_advance_boid, neighbors})
        initial_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      assert_receive {:neighbors_passed_to_advance_boid, []}
    end
  end

  describe "handle_info/2 flocking rule toggles" do
    # Only reads the toggles: changing them here would race with other async tests.
    # Changing them is covered in boid_flocking_rule_toggles_test.exs.
    test "passes the current flocking rule toggles to advance_boid" do
      initial_boid = %Boid{position: {825.0, 975.0}, velocity: {0.0, 0.0}}

      test_pid = self()
      expect(BoidMock, :new, fn -> initial_boid end)

      expect(BoidMock, :advance_boid, fn ^initial_boid, _neighbors, flocking_rule_toggles ->
        send(test_pid, {:toggles_passed_to_advance_boid, flocking_rule_toggles})
        initial_boid
      end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      assert_receive {:toggles_passed_to_advance_boid, flocking_rule_toggles}
      assert flocking_rule_toggles == BoidFlockingRuleToggles.flocking_rule_toggles()
    end
  end

  describe "handle_info/2 tick counting" do
    # The counter is shared by every boid, and other async tests tick boids too,
    # so this checks that the count went up rather than by exactly one.
    test "each tick is counted for the dashboard" do
      initial_boid = %Boid{position: {500.0, 500.0}, velocity: {0.0, 0.0}}
      expect(BoidMock, :new, fn -> initial_boid end)
      expect(BoidMock, :advance_boid, fn boid, _neighbors, _flocking_rule_toggles -> boid end)

      pid = start_supervised!({BoidServer, []})
      tick_count_before = SimulationMetrics.tick_count()

      send(pid, :tick)
      :sys.get_state(pid)

      assert SimulationMetrics.tick_count() > tick_count_before
    end
  end

  # Inserts a row shaped exactly like BoidServer's, owned by a fresh ref standing in
  # for another boid's pid, and removes it after the test.
  defp insert_boid_row(position) do
    {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(position)
    key = {cell_x, cell_y, make_ref()}
    boid = %Boid{position: position, velocity: {0.0, 0.0}}

    :ets.insert(BoidPositions.table_name(), {key, boid})
    on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

    boid
  end

  # Every row belonging to `pid`, in any cell. A full-table match is fine in tests;
  # the point is to prove there is exactly one row per boid.
  defp rows_for(pid) do
    :ets.match_object(BoidPositions.table_name(), {{:_, :_, pid}, :_})
  end
end
