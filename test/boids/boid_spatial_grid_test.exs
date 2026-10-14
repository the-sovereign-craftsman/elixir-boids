defmodule Boids.BoidSpatialGridTest do
  use ExUnit.Case, async: true

  alias Boids.BoidSpatialGrid

  doctest Boids.BoidSpatialGrid

  # 1000.0 world / 50 cell size. The far wall (1000.0) is reachable because
  # Boid.advance_boid clamps to it, so the last valid cell index is 20, inclusive.
  @max_cell 20

  describe "cell_size/0" do
    test "returns the grid cell size" do
      assert BoidSpatialGrid.cell_size() == 50
    end
  end

  describe "cell_for_position/1" do
    test "places the origin in cell {0, 0}" do
      assert BoidSpatialGrid.cell_for_position({0.0, 0.0}) == {0, 0}
    end

    test "truncates each axis independently" do
      assert BoidSpatialGrid.cell_for_position({120.0, 375.0}) == {2, 7}
      assert BoidSpatialGrid.cell_for_position({999.0, 0.0}) == {19, 0}
    end

    test "keeps a position just below a cell boundary in the lower cell" do
      assert BoidSpatialGrid.cell_for_position({49.999, 49.999}) == {0, 0}
    end

    test "places a position exactly on a cell boundary in the higher cell" do
      assert BoidSpatialGrid.cell_for_position({50.0, 50.0}) == {1, 1}
    end

    test "places the far wall in the last cell" do
      assert BoidSpatialGrid.cell_for_position({1000.0, 1000.0}) == {@max_cell, @max_cell}
    end
  end

  describe "surrounding_cells/1" do
    test "returns all 9 cells, including itself, for an interior cell" do
      assert sorted_surrounding({10, 10}) == [
               {9, 9},
               {9, 10},
               {9, 11},
               {10, 9},
               {10, 10},
               {10, 11},
               {11, 9},
               {11, 10},
               {11, 11}
             ]
    end

    test "drops negative cells at the top-left corner" do
      assert sorted_surrounding({0, 0}) == [{0, 0}, {0, 1}, {1, 0}, {1, 1}]
    end

    test "drops cells past the far wall at the bottom-right corner" do
      assert sorted_surrounding({@max_cell, @max_cell}) == [
               {19, 19},
               {19, 20},
               {20, 19},
               {20, 20}
             ]
    end

    test "drops cells past the edge at the top-right and bottom-left corners" do
      assert sorted_surrounding({@max_cell, 0}) == [{19, 0}, {19, 1}, {20, 0}, {20, 1}]
      assert sorted_surrounding({0, @max_cell}) == [{0, 19}, {0, 20}, {1, 19}, {1, 20}]
    end

    test "filters each axis independently along a non-corner edge" do
      assert sorted_surrounding({10, 0}) == [
               {9, 0},
               {9, 1},
               {10, 0},
               {10, 1},
               {11, 0},
               {11, 1}
             ]

      assert sorted_surrounding({@max_cell, 10}) == [
               {19, 9},
               {19, 10},
               {19, 11},
               {20, 9},
               {20, 10},
               {20, 11}
             ]
    end

    test "keeps the last cell for a cell one in from the far wall (upper bound is inclusive)" do
      cells = BoidSpatialGrid.surrounding_cells({19, 19})

      assert length(cells) == 9
      assert {@max_cell, @max_cell} in cells
    end

    test "never returns an out-of-bounds cell and always includes itself, for every cell in the grid" do
      for cell_x <- 0..@max_cell, cell_y <- 0..@max_cell do
        cells = BoidSpatialGrid.surrounding_cells({cell_x, cell_y})

        assert {cell_x, cell_y} in cells

        assert Enum.all?(cells, fn {x, y} -> x in 0..@max_cell and y in 0..@max_cell end),
               "out-of-bounds cell returned for {#{cell_x}, #{cell_y}}: #{inspect(cells)}"
      end
    end

    test "works with cell_for_position for a boid on the far wall" do
      cells =
        {1000.0, 1000.0}
        |> BoidSpatialGrid.cell_for_position()
        |> BoidSpatialGrid.surrounding_cells()

      assert Enum.sort(cells) == [{19, 19}, {19, 20}, {20, 19}, {20, 20}]
    end
  end

  defp sorted_surrounding(cell), do: cell |> BoidSpatialGrid.surrounding_cells() |> Enum.sort()
end
