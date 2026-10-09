defmodule Boids.Boid do
  use GenServer

  @tick_interval_ms 17

  @world_width 1000
  @world_height 1000

  @world_arena %{top: 0, left: 0, width: @world_width, height: @world_height}

  @type t :: %__MODULE__{
    position: {float(), float()},
    velocity: {float(), float()},
  }

  @enforce_keys [:position, :velocity]
  defstruct [:position, :velocity]

  def start_link(_opts) do
    # this should provide a initial position and velocity for the boid and pass that struct as args
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    IO.puts("Inside Boid.init/1")
    boid = %__MODULE__{position: {0.0, 0.0}, velocity: {0.0, 0.0}}
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:ok, boid}
  end

  def handle_info(:tick, %__MODULE__{} = boid) do
    _valid_width = @world_arena.width - 1
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:noreply, boid}
  end
end
