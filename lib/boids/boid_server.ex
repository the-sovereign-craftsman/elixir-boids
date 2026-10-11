defmodule Boids.BoidServer do
  use GenServer

  @tick_interval_ms 200

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    IO.puts("Inside Boid.init/1")

    boid = boid_module().new()
    IO.inspect(boid, label: "boid after random position generation")
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:ok, boid}
  end

  def handle_info(:tick, boid) do
    Process.send_after(self(), :tick, @tick_interval_ms)
    new_boid = boid_module().advance_boid(boid)
    IO.inspect(new_boid, label: "new boid after clamping")
    {:noreply, new_boid}
  end

  defp boid_module(), do: Application.get_env(:boids, :boid_module)
end
