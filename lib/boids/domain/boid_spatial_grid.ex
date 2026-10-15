defmodule Boids.BoidSpatialGrid do
  @moduledoc """
  Pure math for dividing the world into a uniform grid of square cells, so
  neighbor searches only look at nearby boids instead of all of them.

  A position maps to the cell containing it, and a cell maps to the block of
  up to 9 cells (itself plus 8 neighbors, clipped at the world edges) that a
  neighbor search must cover. The cell size must be at least the neighbor
  radius, so that block is guaranteed to contain every possible neighbor.

  Depends on `Boids.World` for the grid bounds and Boids.BoidFlockingConfig for the perception radius.
  """

  alias Boids.BoidFlockingConfig

  @spatial_grid_cell_size BoidFlockingConfig.boid_perception_radius()
  @neighbor_offsets for dx <- -1..1, dy <- -1..1, do: {dx, dy}
  @max_cell_x trunc(Boids.World.world_arena().width / @spatial_grid_cell_size)
  @max_cell_y trunc(Boids.World.world_arena().height / @spatial_grid_cell_size)

  @type position :: {float(), float()}
  @type cell :: {integer(), integer()}

  @spec cell_size() :: pos_integer()
  def cell_size, do: @spatial_grid_cell_size

  @doc """
  Returns the `{cell_x, cell_y}` cell containing `position`.

  Each axis is divided by the cell size and truncated, which counts how
  many whole cells fit between the world's edge and the position. With a
  cell size of 50, `x = 120` gives `120 / 50 = 2.4`, truncated to `2`:

  ```text
  0        50       100  120  150
  ├────────┼────────┼────┼────┤
    cell 0   cell 1   cell 2
                        ↑ position
  ```

  Two full cells (0–50 and 50–100) fit before 120, so it falls in the
  third cell, index 2. The y axis is computed the same way, independently.

  ## Examples

    iex> Boids.BoidSpatialGrid.cell_for_position({120.0, 375.0})
    {2, 7}
  """
  @spec cell_for_position(position()) :: cell()
  def cell_for_position({x, y}) do
    cell_x = trunc(x / @spatial_grid_cell_size)
    cell_y = trunc(y / @spatial_grid_cell_size)
    {cell_x, cell_y}
  end

  @spec surrounding_cells(cell()) :: [cell()]
  def surrounding_cells({x, y}) do
    @neighbor_offsets
    |> Enum.map(fn {dx, dy} -> {x + dx, y + dy} end)
    |> Enum.filter(fn {cell_x, cell_y} ->
      cell_x in 0..@max_cell_x and cell_y in 0..@max_cell_y
    end)
  end
end
