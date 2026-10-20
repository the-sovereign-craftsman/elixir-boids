defmodule Boids.BoidServer do
  @moduledoc """
  The process for a single boid. One runs per boid under
  `Boids.DynamicSupervisor`.

  On a self-rescheduling tick it advances its boid through the configured
  boid module and publishes the result to the `Boids.BoidPositions` ETS
  table, keyed by `{cell_x, cell_y, pid}`. When the boid crosses into a new
  `Boids.BoidSpatialGrid` cell, the row under the old key is deleted.

  When it stops, it deletes its own row in `terminate/2`, so a removed boid
  doesn't stay frozen on the canvas or keep counting as a neighbor. It traps
  exits so that `terminate/2` also runs when its supervisor stops it. A boid
  killed with `Process.exit(pid, :kill)` skips `terminate/2` and still leaves
  its row behind.

  The server holds no simulation logic of its own; that lives in the boid
  module (`Boids.Boid` by default).
  """

  use GenServer

  alias Boids.BoidFlockingConfig
  alias Boids.BoidFlockingRuleToggles
  alias Boids.BoidPositions
  alias Boids.BoidSpatialGrid

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    # Turns the supervisor's shutdown signal into a message, so GenServer runs
    # terminate/2 (and deletes this boid's row) before the process exits.
    Process.flag(:trap_exit, true)

    boid = boid_module().new()
    {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(boid.position)

    :ets.insert(BoidPositions.table_name(), {{cell_x, cell_y, self()}, boid})

    schedule_tick()
    {:ok, boid}
  end

  @impl true
  def handle_info(:tick, boid) do
    {old_cell_x, old_cell_y} = old_cell = BoidSpatialGrid.cell_for_position(boid.position)

    # Look up neighbors and filter based on perception radius
    neighbors =
      BoidPositions.boids_within_radius(
        boid.position,
        BoidFlockingConfig.boid_perception_radius(),
        self()
      )

    flocking_rule_toggles = BoidFlockingRuleToggles.flocking_rule_toggles()

    new_boid = boid_module().advance_boid(boid, neighbors, flocking_rule_toggles)
    {new_cell_x, new_cell_y} = new_cell = BoidSpatialGrid.cell_for_position(new_boid.position)

    :ets.insert(BoidPositions.table_name(), {{new_cell_x, new_cell_y, self()}, new_boid})

    if old_cell != new_cell do
      :ets.delete(BoidPositions.table_name(), {old_cell_x, old_cell_y, self()})
    end

    schedule_tick()
    {:noreply, new_boid}
  end

  # The boid's row is keyed by the cell of its last position, which is the state.
  @impl true
  def terminate(_reason, boid) do
    {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(boid.position)
    :ets.delete(BoidPositions.table_name(), {cell_x, cell_y, self()})
  end

  # :manual (set in config/test.exs) skips the timer so tests control every tick.
  defp schedule_tick do
    case Application.fetch_env!(:boids, :tick_interval_ms) do
      :manual -> :ok
      interval_ms -> Process.send_after(self(), :tick, interval_ms)
    end
  end

  # DI to allow us to mock boid module from our tests
  defp boid_module, do: Application.get_env(:boids, :boid_module)
end
