defmodule Boids.BoidPositions do
  @moduledoc """
  Owns the shared `:boid_positions` ETS table, where every boid publishes its
  latest state.

  The table is an `:ordered_set` of `{{cell_x, cell_y, pid}, %Boids.Boid{}}`
  rows. Ordering by cell first lets readers fetch all boids in a cell with a
  prefix range scan instead of scanning the whole table. It is `:public` so
  boid processes write their own rows directly, without a bottleneck through
  this process.

  This process exists only so the table has a supervised, long-lived owner.
  Rows of boids that die are not yet cleaned up.
  """

  use GenServer

  @table_name :boid_positions

  def table_name, do: @table_name

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [
      :ordered_set,
      :public,
      :named_table,
      write_concurrency: true,
      read_concurrency: true
    ])

    {:ok, @table_name}
  end
end
