defmodule Boids.BoidServerTest do
  use ExUnit.Case, async: true

  import Mox

  alias Boids.Boid
  alias Boids.BoidMock
  alias Boids.BoidPositions
  alias Boids.BoidServer
  alias Boids.BoidSpatialGrid

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
      expect(BoidMock, :advance_boid, fn ^initial_boid -> advanced_boid end)

      pid = start_supervised!({BoidServer, []})
      send(pid, :tick)

      assert :sys.get_state(pid) == advanced_boid
    end

    test "overwrites its row in the positions table on :tick" do
      initial_boid = %Boid{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
      advanced_boid = %Boid{position: {1.0, 1.0}, velocity: {1.0, 1.0}}

      expect(BoidMock, :new, fn -> initial_boid end)
      expect(BoidMock, :advance_boid, fn ^initial_boid -> advanced_boid end)

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
      expect(BoidMock, :advance_boid, fn ^initial_boid -> advanced_boid end)

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
      expect(BoidMock, :advance_boid, fn ^initial_boid -> advanced_boid end)

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
      expect(BoidMock, :advance_boid, fn ^boid_0 -> boid_1 end)
      expect(BoidMock, :advance_boid, fn ^boid_1 -> boid_2 end)
      expect(BoidMock, :advance_boid, fn ^boid_2 -> boid_3 end)

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

  # Every row belonging to `pid`, in any cell. A full-table match is fine in tests;
  # the point is to prove there is exactly one row per boid.
  defp rows_for(pid) do
    :ets.match_object(BoidPositions.table_name(), {{:_, :_, pid}, :_})
  end
end
