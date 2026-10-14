defmodule BoidsTest do
  use ExUnit.Case, async: true

  alias Boids.Boid
  alias Boids.BoidPositions

  describe "list_boid_positions/0" do
    test "returns rows written to the positions table" do
      # Real row shape; a ref stands in for the pid so the key is unique in the shared table.
      key = {0, 0, make_ref()}
      boid = %Boid{position: {12.0, 34.0}, velocity: {1.0, 1.0}}

      :ets.insert(BoidPositions.table_name(), {key, boid})
      on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

      # The table is shared with other async tests, so check membership, not equality.
      assert {key, boid} in Boids.list_boid_positions()
    end
  end
end
