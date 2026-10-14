defmodule Boids.World do
  @moduledoc """
  The dimensions of the simulation arena, in world units.

  This is the single source of truth for the arena's size. `Boids.Boid` uses
  it for movement bounds and `Boids.BoidSpatialGrid` uses it for grid bounds.
  Values are compile-time constants, so dependent modules can read them in
  module attributes.
  """

  @world_width 1000.0
  @world_height 1000.0

  @world_arena %{top: 0.0, left: 0.0, width: @world_width, height: @world_height}

  @spec world_arena() :: %{top: float(), left: float(), width: float(), height: float()}
  def world_arena, do: @world_arena
end
