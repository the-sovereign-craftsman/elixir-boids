defmodule Boids.BoidServerTest do
  use ExUnit.Case, async: true

  import Mox

  alias Boids.Boid
  alias Boids.BoidMock
  alias Boids.BoidPositions
  alias Boids.BoidServer

  setup :verify_on_exit!

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

      assert :ets.lookup(BoidPositions.table_name(), pid) == [{pid, initial_boid}]
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

      assert :ets.lookup(BoidPositions.table_name(), pid) == [{pid, advanced_boid}]
    end
  end
end
