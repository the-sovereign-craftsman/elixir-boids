defmodule Boids.BoidFlockingConfigTest do
  use ExUnit.Case, async: true

  alias Boids.BoidFlockingConfig
  alias Boids.BoidSpatialGrid

  describe "boid_perception_radius/0" do
    test "is a positive integer" do
      radius = BoidFlockingConfig.boid_perception_radius()

      assert is_integer(radius)
      assert radius > 0
    end

    test "is the spatial grid's cell size, so a 3x3 cell search always covers the radius" do
      assert BoidSpatialGrid.cell_size() == BoidFlockingConfig.boid_perception_radius()
    end
  end
end
