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
    match_spec_guards = [
      {:"=/=", :"$1", pid},
      {:"=<", squared_distance_to(position_x, position_y), radius * radius}
    ]

    position
    |> BoidSpatialGrid.cell_for_position()
    |> BoidSpatialGrid.surrounding_cells()
    |> Enum.flat_map(&boids_in_cell_matching(&1, match_spec_guards))
  end

  # Reading a row copies it out of ETS into the reading process. So rather than copying
  # every row in the cell and filtering in Elixir, the match spec runs the filter inside
  # ETS, and only the boids that pass are copied out. The 3x3 cells searched cover about
  # three times the area of the perception circle, so about two thirds of the rows are
  # never copied.
  #
  # In the match spec, $1 is the row's pid and $2 and $3 are the boid's x and y. Binding
  # the cell in the key keeps each select a range scan over one cell, not the whole table.
  @spec boids_in_cell_matching(BoidSpatialGrid.cell(), list()) :: [Boid.t()]
  defp boids_in_cell_matching({cell_x, cell_y}, match_spec_guards) do
    row_pattern = {{cell_x, cell_y, :"$1"}, %{position: {:"$2", :"$3"}}}
    # :"$_" is the whole matched row, {key, boid}; element 2 is the boid.
    returned_boid = {:element, 2, :"$_"}

    :ets.select(@table_name, [{row_pattern, match_spec_guards, [returned_boid]}])
  end

  # The squared distance from {position_x, position_y} to the row's boid, as a match
  # spec expression: (x - position_x)^2 + (y - position_y)^2. Compared against the
  # squared radius, which avoids a square root.
  defp squared_distance_to(position_x, position_y) do
    delta_x = {:-, :"$2", position_x}
    delta_y = {:-, :"$3", position_y}
    {:+, {:*, delta_x, delta_x}, {:*, delta_y, delta_y}}
  end
end
