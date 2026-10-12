defmodule Boids.BoidPositions do
  use GenServer

  @table_name :boid_positions

  def table_name(), do: @table_name

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      write_concurrency: true,
      read_concurrency: true
    ])

    {:ok, @table_name}
  end
end
