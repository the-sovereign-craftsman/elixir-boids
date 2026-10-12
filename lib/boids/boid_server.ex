defmodule Boids.BoidServer do
  use GenServer

  alias Boids.BoidPositions

  @tick_interval_ms 33

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    boid = boid_module().new()

    :ets.insert(BoidPositions.table_name(), {self(), boid})
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:ok, boid}
  end

  @impl true
  def handle_info(:tick, boid) do
    Process.send_after(self(), :tick, @tick_interval_ms)
    new_boid = boid_module().advance_boid(boid)
    :ets.insert(BoidPositions.table_name(), {self(), new_boid})
    {:noreply, new_boid}
  end

  defp boid_module(), do: Application.get_env(:boids, :boid_module)
end
