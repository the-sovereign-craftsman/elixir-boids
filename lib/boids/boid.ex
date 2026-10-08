defmodule Boids.Boid do
  use GenServer

  @tick_interval_ms 17

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    IO.inspect(args, label: "Inside Boid.init/1")
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:ok, args}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:noreply, state}
  end
end
