defmodule Boids.World do
  @world_width 1000.0
  @world_height 1000.0

  @world_arena %{top: 0.0, left: 0.0, width: @world_width, height: @world_height}

  @spec world_arena() :: %{top: float(), left: float(), width: float(), height: float()}
  def world_arena(), do: @world_arena
end
