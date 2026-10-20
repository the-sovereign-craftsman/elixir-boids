defmodule Boids.BoidJanitor do
  @moduledoc """
  Cleans up after boids that die, and counts the ones that crash.

  Every `Boids.BoidServer` registers itself here when it starts, and the janitor
  monitors it. When a boid dies, the janitor gets a `:DOWN` message and:

    * if the boid was killed with `:kill`, deletes its rows from the
      `Boids.BoidPositions` table. Every other way a boid stops runs its own
      `terminate/2`, which deletes its row, but a `:kill` skips it. Without this, a
      killed boid would stay frozen on the canvas and keep counting as a neighbor.
    * counts the death as a crash unless it was a normal exit. Boids removed on
      purpose (flock size, Clear all) stop with `:shutdown` and aren't restarted,
      so they aren't counted. Every crash of a `:permanent` boid leads to one
      restart, which is why the dashboard shows this count as "Restarts".

  It monitors rather than links, so it hears about every death but never dies with
  a boid. It is restarted whenever the positions table's owner dies (see
  `Boids.BoidPositionsSupervisor`), and on starting it adopts every boid that is
  already running, so no boid goes unwatched.
  """

  use GenServer

  alias Boids.BoidPositions

  # The crash count lives in a :counters ref rather than in this process's state, so it
  # survives the janitor being restarted (see Boids.BoidPositionsSupervisor).
  @crash_counter_key {__MODULE__, :crash_counter}

  @type state :: %{watched_boid_pids: MapSet.t(pid())}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Starts watching a boid. A cast, so a boid starting up never waits on the janitor,
  even while it is busy cleaning up after a mass kill.
  """
  @spec watch_boid(pid()) :: :ok
  def watch_boid(pid), do: GenServer.cast(__MODULE__, {:watch_boid, pid})

  @doc "How many watched boids have crashed or been killed since the app started."
  @spec crash_count() :: non_neg_integer()
  def crash_count do
    @crash_counter_key
    |> :persistent_term.get()
    |> :counters.get(1)
  end

  # A restarted janitor has no monitors, so it adopts every boid that is already
  # running. Boids that start from now on register themselves with watch_boid/1.
  @impl true
  def init(:ok) do
    ensure_crash_counter_exists()

    watched_boid_pids =
      Enum.reduce(running_boid_pids(), MapSet.new(), &watch_unless_watched/2)

    {:ok, %{watched_boid_pids: watched_boid_pids}}
  end

  @impl true
  def handle_cast({:watch_boid, pid}, state) do
    {:noreply, %{state | watched_boid_pids: watch_unless_watched(pid, state.watched_boid_pids)}}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, exit_reason}, state) do
    if left_rows_behind?(exit_reason) do
      delete_rows_for(pid)
    end

    if crash?(exit_reason) do
      @crash_counter_key
      |> :persistent_term.get()
      |> :counters.add(1, 1)
    end

    {:noreply, %{state | watched_boid_pids: MapSet.delete(state.watched_boid_pids, pid)}}
  end

  # Created once, the first time any janitor starts. A restarted janitor keeps it.
  defp ensure_crash_counter_exists do
    if :persistent_term.get(@crash_counter_key, nil) == nil do
      :persistent_term.put(@crash_counter_key, :counters.new(1, [:write_concurrency]))
    end
  end

  # When the janitor first starts at boot, the boid supervisor doesn't exist yet, and
  # there are no boids to adopt.
  defp running_boid_pids do
    if Process.whereis(Boids.DynamicSupervisor), do: Boids.boid_pids(), else: []
  end

  # A boid can be both adopted in init/1 and register itself, if it starts while the
  # janitor is starting. Monitoring it twice would count its death twice.
  defp watch_unless_watched(pid, watched_boid_pids) do
    if MapSet.member?(watched_boid_pids, pid) do
      watched_boid_pids
    else
      Process.monitor(pid)
      MapSet.put(watched_boid_pids, pid)
    end
  end

  # The row's key is {cell_x, cell_y, pid}, and the janitor doesn't know the cell, so
  # this scans the whole table. Fine for a demo; tracking each boid's last cell would
  # avoid the scan if it ever matters. If the table's owner has just died, the table and
  # every row in it are already gone, so there is nothing to delete.
  defp delete_rows_for(pid) do
    if :ets.whereis(BoidPositions.table_name()) != :undefined do
      :ets.match_delete(BoidPositions.table_name(), {{:_, :_, pid}, :_})
    end
  end

  # Boids trap exits, so whether they stop, are removed or crash, their own terminate/2
  # deletes their row. Only a :kill skips terminate/2. With :noproc the real reason is
  # lost, so the janitor cleans up to be safe. Skipping the rest matters: each delete
  # scans the whole table, and clearing 5,000 boids would otherwise mean 5,000 scans.
  defp left_rows_behind?(:killed), do: true
  defp left_rows_behind?(:noproc), do: true
  defp left_rows_behind?(_exit_reason), do: false

  defp crash?(:normal), do: false
  defp crash?(:shutdown), do: false
  defp crash?({:shutdown, _details}), do: false
  # The boid was already dead when the janitor started watching it, so the real exit
  # reason is lost. Not counted, rather than guessed.
  defp crash?(:noproc), do: false
  defp crash?(_abnormal_reason), do: true
end
