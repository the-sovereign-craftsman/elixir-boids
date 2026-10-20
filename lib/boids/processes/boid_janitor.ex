defmodule Boids.BoidJanitor do
  @moduledoc """
  Cleans up after boids that die, and counts the ones that crash.

  Every `Boids.BoidServer` registers itself here when it starts, and the janitor
  monitors it. When a boid dies, the janitor gets a `:DOWN` message and:

    * deletes every row for that pid from the `Boids.BoidPositions` table. A boid
      deletes its own row in `terminate/2`, but one killed with `:kill` never runs
      it. Without this, a killed boid would stay frozen on the canvas and keep
      counting as a neighbor. Deleting a row that is already gone does nothing, so
      running both is safe.
    * counts the death as a crash unless it was a normal exit. Boids removed on
      purpose (flock size, Clear all) stop with `:shutdown` and aren't restarted,
      so they aren't counted. Every crash of a `:permanent` boid leads to one
      restart, which is why the dashboard shows this count as "Restarts".

  It monitors rather than links, so it hears about every death but never dies with
  a boid. It is separate from `Boids.BoidPositions`, which a later failure scenario
  kills on purpose.
  """

  use GenServer

  alias Boids.BoidPositions

  @type state :: %{crash_count: non_neg_integer()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Starts watching a boid. A cast, so a boid starting up never waits on the janitor,
  even while it is busy cleaning up after a mass kill.
  """
  @spec watch_boid(pid()) :: :ok
  def watch_boid(pid), do: GenServer.cast(__MODULE__, {:watch_boid, pid})

  @doc "How many watched boids have crashed or been killed since the janitor started."
  @spec crash_count() :: non_neg_integer()
  def crash_count, do: GenServer.call(__MODULE__, :crash_count)

  @impl true
  def init(:ok), do: {:ok, %{crash_count: 0}}

  @impl true
  def handle_cast({:watch_boid, pid}, state) do
    Process.monitor(pid)
    {:noreply, state}
  end

  @impl true
  def handle_call(:crash_count, _from, state), do: {:reply, state.crash_count, state}

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, exit_reason}, state) do
    # The row's key is {cell_x, cell_y, pid}, and the janitor doesn't know the cell,
    # so this scans the whole table. Fine for a demo; tracking each boid's last cell
    # would avoid the scan if it ever matters.
    :ets.match_delete(BoidPositions.table_name(), {{:_, :_, pid}, :_})

    if crash?(exit_reason) do
      {:noreply, %{state | crash_count: state.crash_count + 1}}
    else
      {:noreply, state}
    end
  end

  defp crash?(:normal), do: false
  defp crash?(:shutdown), do: false
  defp crash?({:shutdown, _details}), do: false
  # The boid was already dead when the janitor started watching it, so the real exit
  # reason is lost. Not counted, rather than guessed.
  defp crash?(:noproc), do: false
  defp crash?(_abnormal_reason), do: true
end
