defmodule Boids.BoidPositions do
  @moduledoc """
  Owns the shared `:boid_positions` ETS table, where every boid publishes its
  latest state.

  The table is an `:ordered_set` of `{{cell_x, cell_y, pid}, %Boids.Boid{}}`
  rows. Ordering by cell first lets readers fetch all boids in a cell with a
  prefix range scan instead of scanning the whole table. It is `:public` so
  boid processes write their own rows directly, without a bottleneck through
  this process.

  This process exists only so the table has a supervised, long-lived owner. An
  ETS table is deleted when its owner dies, so this process dying takes every row
  with it (see `Boids.kill_boid_positions_owner/0`). Each boid deletes its own row
  when it stops (see `Boids.BoidServer`), and `Boids.BoidJanitor` deletes the rows
  of boids killed with `Process.exit(pid, :kill)`.
  """

  use GenServer

  alias Boids.Boid
  alias Boids.BoidSpatialGrid

  @table_name :boid_positions
  @max_query_radius BoidSpatialGrid.cell_size()

  @typedoc "Key for a row: the boid's grid cell first (for prefix range scans), then its pid."
  @type row_key :: {cell_x :: integer(), cell_y :: integer(), pid()}

  @typedoc "One row in the positions table."
  @type row :: {row_key(), Boid.t()}

  def table_name, do: @table_name

  def start_link(_opts) do
    # Registered so the failure demo can find it (Boids.kill_boid_positions_owner/0).
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [
      :ordered_set,
      :public,
      :named_table,
      write_concurrency: true,
      read_concurrency: true
    ])

    {:ok, @table_name}
  end

  @spec boids_within_radius(BoidSpatialGrid.position(), pos_integer(), pid()) :: [Boid.t()]
  def boids_within_radius({position_x, position_y} = position, radius, pid)
      when radius <= @max_query_radius do
    radius_squared = radius * radius

    position
    |> BoidSpatialGrid.cell_for_position()
    |> BoidSpatialGrid.surrounding_cells()
    |> Enum.flat_map(&rows_in_cell/1)
    |> Enum.reject(fn {{_cell_x, _cell_y, row_pid}, _boid} -> row_pid == pid end)
    |> Enum.filter(fn {_key, %Boid{position: {neighbor_x, neighbor_y}}} ->
      delta_x = neighbor_x - position_x
      delta_y = neighbor_y - position_y
      delta_x * delta_x + delta_y * delta_y <= radius_squared
    end)
    |> Enum.map(fn {_key, boid} -> boid end)
  end

  @spec rows_in_cell(BoidSpatialGrid.cell()) :: [row()]
  defp rows_in_cell({cell_x, cell_y}) do
    :ets.match_object(@table_name, {{cell_x, cell_y, :_}, :_})
  end
end
