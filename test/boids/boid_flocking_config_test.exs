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

  describe "boid_separation_radius/0" do
    test "is positive and inside the perception radius, so every boid to repel is a neighbor" do
      separation_radius = BoidFlockingConfig.boid_separation_radius()

      assert separation_radius > 0
      assert separation_radius < BoidFlockingConfig.boid_perception_radius()
    end
  end

  describe "boid_separation_weight/0" do
    test "is positive, so separation pushes boids apart rather than together" do
      assert BoidFlockingConfig.boid_separation_weight() > 0
    end
  end

  describe "speed limits" do
    test "the min speed is positive and below the max speed" do
      assert BoidFlockingConfig.boid_min_speed() > 0
      assert BoidFlockingConfig.boid_min_speed() < BoidFlockingConfig.boid_max_speed()
    end

    test "the initial speed is within the speed limits" do
      initial_speed = BoidFlockingConfig.boid_initial_speed()

      assert initial_speed >= BoidFlockingConfig.boid_min_speed()
      assert initial_speed <= BoidFlockingConfig.boid_max_speed()
    end

    test "the max speed is below the separation radius, so a boid can't skip past a neighbor in one tick" do
      assert BoidFlockingConfig.boid_max_speed() < BoidFlockingConfig.boid_separation_radius()
    end
  end
end
