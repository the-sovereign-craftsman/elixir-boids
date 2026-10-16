defmodule Boids.BoidPositionsTest do
  use ExUnit.Case, async: true

  alias Boids.Boid
  alias Boids.BoidPositions
  alias Boids.BoidSpatialGrid

  # The table is created once by the application's supervision tree, so these
  # tests inspect that running instance rather than starting a new one (a
  # second :named_table with the same name would fail to start).

  describe "table" do
    test "is a named :ordered_set table" do
      assert :ets.info(BoidPositions.table_name(), :named_table) == true
      assert :ets.info(BoidPositions.table_name(), :type) == :ordered_set
    end

    test "is writable from a process other than its owner" do
      # Real row shape, since the LiveView reads every row in this shared table.
      key = {0, 0, make_ref()}
      boid = %Boid{position: {10.0, 10.0}, velocity: {0.0, 0.0}}
      on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

      # The test process does not own the table, so this only works if it's :public.
      assert :ets.insert(BoidPositions.table_name(), {key, boid})
      assert :ets.lookup(BoidPositions.table_name(), key) == [{key, boid}]
    end
  end

  describe "boids_within_radius/3" do
    # The table is shared with every async test, so each test works in its own
    # region of the world, far enough from the others that their rows can never
    # fall inside each other's search.
    #
    # Most tests pass a radius of 25 rather than the configured perception
    # radius, so they keep testing the same geometry if that config changes.
    # 15-20-25 is a right triangle, so a boid offset by {15, 20} sits exactly
    # on the radius.
    @radius 25

    test "returns boids inside the radius and exactly on it" do
      center = {225.0, 225.0}
      inside = insert_boid_row({230.0, 230.0})
      on_the_radius = insert_boid_row({240.0, 245.0})

      assert sorted_boids_within_radius(center, @radius, self()) ==
               Enum.sort([inside, on_the_radius])
    end

    test "excludes boids just beyond the radius, including diagonals in neighboring cells" do
      center = {425.0, 225.0}
      # Distance from {15, 20.5} is ~25.4.
      insert_boid_row({440.0, 245.5})
      # Distance from {20, 20} is ~28.3: within both axes' range, but too far in a straight line.
      insert_boid_row({445.0, 245.0})

      assert BoidPositions.boids_within_radius(center, @radius, self()) == []
    end

    test "finds neighbors in an adjacent cell across a cell boundary" do
      # {645.0, 225.0} is in cell {12, 4}; {655.0, 225.0} is in cell {13, 4}.
      center = {645.0, 225.0}
      neighbor = insert_boid_row({655.0, 225.0})

      assert BoidPositions.boids_within_radius(center, @radius, self()) == [neighbor]
    end

    test "ignores boids far away in other cells" do
      center = {225.0, 425.0}
      insert_boid_row({425.0, 425.0})

      assert BoidPositions.boids_within_radius(center, @radius, self()) == []
    end

    test "excludes the caller's own row" do
      center = {825.0, 225.0}
      insert_boid_row(center, self())
      other = insert_boid_row({830.0, 225.0})

      assert BoidPositions.boids_within_radius(center, @radius, self()) == [other]
    end

    test "returns plain boid structs, not table rows" do
      center = {425.0, 625.0}
      insert_boid_row({430.0, 625.0})

      assert [%Boid{}] = BoidPositions.boids_within_radius(center, @radius, self())
    end

    test "accepts a radius up to the grid's cell size" do
      center = {825.0, 625.0}

      assert BoidPositions.boids_within_radius(center, BoidSpatialGrid.cell_size(), self()) == []
    end

    test "rejects a radius larger than the grid's cell size, since the 3x3 search would miss neighbors" do
      center = {825.0, 625.0}

      assert_raise FunctionClauseError, fn ->
        BoidPositions.boids_within_radius(center, BoidSpatialGrid.cell_size() + 1, self())
      end
    end
  end

  # Inserts a row shaped exactly like BoidServer's, owned by `owner` (a fresh ref
  # by default, standing in for another boid's pid), and removes it after the test.
  defp insert_boid_row(position, owner \\ make_ref()) do
    {cell_x, cell_y} = BoidSpatialGrid.cell_for_position(position)
    key = {cell_x, cell_y, owner}
    boid = %Boid{position: position, velocity: {0.0, 0.0}}

    :ets.insert(BoidPositions.table_name(), {key, boid})
    on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

    boid
  end

  defp sorted_boids_within_radius(position, radius, pid) do
    position |> BoidPositions.boids_within_radius(radius, pid) |> Enum.sort()
  end
end
