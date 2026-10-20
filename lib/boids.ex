defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Boids.BoidFlockingRuleToggles
  alias Boids.BoidJanitor
  alias Boids.BoidPositions
  alias Boids.SimulationMetrics

  # The most boids set_boid_count/1 will allow. spawn_boids/1 ignores it, so iex can go past it
  # for performance experiments.
  @max_boid_count 5_000

  @spec spawn_boid() :: pid()
  def spawn_boid do
    {:ok, pid} = DynamicSupervisor.start_child(Boids.DynamicSupervisor, Boids.BoidServer)
    pid
  end

  @spec spawn_boids(non_neg_integer()) :: [pid()]
  def spawn_boids(count) do
    # The //1 step makes 1..0 an empty range, so a count of 0 spawns nothing.
    # Without it, 1..0 counts down and spawns two boids.
    Enum.map(1..count//1, fn _ -> spawn_boid() end)
  end

  @doc "The most boids `set_boid_count/1` will allow at once."
  @spec max_boid_count() :: pos_integer()
  def max_boid_count, do: @max_boid_count

  @doc "How many boid processes are alive right now."
  @spec boid_count() :: non_neg_integer()
  def boid_count do
    DynamicSupervisor.count_children(Boids.DynamicSupervisor).active
  end

  @doc """
  Spawns or removes boids until there are `target_count`, capped at
  `max_boid_count/0`. Returns the new number of boids.
  """
  @spec set_boid_count(non_neg_integer()) :: non_neg_integer()
  def set_boid_count(target_count) when is_integer(target_count) and target_count >= 0 do
    capped_target_count = min(target_count, @max_boid_count)
    current_count = boid_count()

    cond do
      capped_target_count > current_count -> spawn_boids(capped_target_count - current_count)
      capped_target_count < current_count -> remove_boids(current_count - capped_target_count)
      true -> :ok
    end

    boid_count()
  end

  @doc "Stops `count` boids. Each one deletes its own row as it stops."
  @spec remove_boids(non_neg_integer()) :: :ok
  def remove_boids(count) when is_integer(count) and count >= 0 do
    boid_pids()
    |> Enum.take(count)
    |> Enum.each(&DynamicSupervisor.terminate_child(Boids.DynamicSupervisor, &1))
  end

  @doc "Stops every boid."
  @spec remove_all_boids() :: :ok
  def remove_all_boids, do: remove_boids(boid_count())

  @doc """
  Kills `count` random boids with `Process.exit(pid, :kill)`, which can't be
  trapped, so they die without running `terminate/2`. Their supervisor restarts
  each one as a fresh boid at a random position, and `Boids.BoidJanitor` deletes
  the dead boids' rows and counts the deaths. Returns how many were killed, which
  is every boid when `count` is more than there are.
  """
  @spec kill_boids(non_neg_integer()) :: non_neg_integer()
  def kill_boids(count) when is_integer(count) and count >= 0 do
    boid_pids_to_kill = Enum.take_random(boid_pids(), count)

    Enum.each(boid_pids_to_kill, &Process.exit(&1, :kill))

    length(boid_pids_to_kill)
  end

  @doc """
  The pids of the boids that are running right now. A boid its supervisor is in the
  middle of restarting has no process yet, so it isn't included.
  """
  @spec boid_pids() :: [pid()]
  def boid_pids, do: running_child_pids(Boids.DynamicSupervisor)

  @doc """
  Corrupts the state of `count` random boids, so each one crashes on its next tick:
  a bug in the boid's own code, rather than a kill from outside.

  `:sys.replace_state/2` swaps the boid's velocity for the atom `:corrupted`. The boid
  keeps running until its next tick, when `Boids.Boid.advance_boid/3` can't match a
  `{x, y}` velocity and raises. Its supervisor restarts it as a fresh boid, and
  `Boids.BoidJanitor` counts the crash. Returns how many were corrupted.
  """
  @spec crash_boids(non_neg_integer()) :: non_neg_integer()
  def crash_boids(count) when is_integer(count) and count >= 0 do
    boid_pids()
    |> Enum.take_random(count)
    |> Enum.count(&corrupt_boid_state/1)
  end

  # :sys.replace_state/2 is a call to the boid, so it exits if the boid dies first (say,
  # killed at the same moment). That boid is skipped rather than crashing the caller.
  defp corrupt_boid_state(pid) do
    :sys.replace_state(pid, fn boid -> %{boid | velocity: :corrupted} end)
    true
  catch
    :exit, _boid_already_dead -> false
  end

  @doc """
  Kills the process that owns the positions table, with `Process.exit(pid, :kill)`.
  An ETS table is deleted when its owner dies, so every boid's row goes with it.
  What happens next depends on the supervision tree, which is the point of the demo.
  """
  @spec kill_boid_positions_owner() :: :ok
  def kill_boid_positions_owner do
    case Process.whereis(BoidPositions) do
      nil ->
        :ok

      owner_pid ->
        Process.exit(owner_pid, :kill)
        :ok
    end
  end

  @doc "Starts one CPU hog: a process that spins forever. See `Boids.CpuHog`."
  @spec start_cpu_hog() :: pid()
  def start_cpu_hog do
    {:ok, pid} = DynamicSupervisor.start_child(Boids.CpuHogSupervisor, Boids.CpuHog)
    pid
  end

  @doc "Starts `count` CPU hogs."
  @spec start_cpu_hogs(non_neg_integer()) :: [pid()]
  def start_cpu_hogs(count) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _ -> start_cpu_hog() end)
  end

  @doc "Stops every CPU hog."
  @spec stop_cpu_hogs() :: :ok
  def stop_cpu_hogs do
    Boids.CpuHogSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      DynamicSupervisor.terminate_child(Boids.CpuHogSupervisor, pid)
    end)
  end

  @doc "The pids of the CPU hogs that are running right now."
  @spec cpu_hog_pids() :: [pid()]
  def cpu_hog_pids, do: running_child_pids(Boids.CpuHogSupervisor)

  @doc "How many CPU hogs are running."
  @spec cpu_hog_count() :: non_neg_integer()
  def cpu_hog_count, do: DynamicSupervisor.count_children(Boids.CpuHogSupervisor).active

  @doc "How many boids have crashed or been killed. See `Boids.BoidJanitor`."
  defdelegate boid_crash_count(), to: BoidJanitor, as: :crash_count

  # A child its supervisor is in the middle of restarting is listed with :restarting
  # where its pid would be. There's no process to stop, kill or measure yet, so it's skipped.
  defp running_child_pids(supervisor) do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(supervisor),
        is_pid(pid),
        do: pid
  end

  @spec list_boid_positions() :: [{pid(), Boids.Boid.t()}]
  def list_boid_positions do
    :ets.tab2list(BoidPositions.table_name())
  end

  @doc "Whether each flocking rule is on. See `Boids.BoidFlockingRuleToggles`."
  defdelegate flocking_rule_toggles(), to: BoidFlockingRuleToggles

  @doc "Subscribes the caller to flocking rule toggle changes. See `Boids.BoidFlockingRuleToggles`."
  defdelegate subscribe_to_flocking_rule_toggles(), to: BoidFlockingRuleToggles

  @doc "Turns every flocking rule on or off. See `Boids.BoidFlockingRuleToggles`."
  defdelegate update_all_flocking_rule_toggles(enabled?), to: BoidFlockingRuleToggles

  @doc "Turns one flocking rule on or off. See `Boids.BoidFlockingRuleToggles`."
  defdelegate update_flocking_rule_toggles(rule, enabled?), to: BoidFlockingRuleToggles

  @doc """
  Subscribes the caller to a metrics snapshot every second, sent as
  `{:simulation_metrics_updated, snapshot, history}`. See `Boids.SimulationMetrics`.
  """
  defdelegate subscribe_to_simulation_metrics(), to: SimulationMetrics

  @doc "How many times per second each boid should tick. See `Boids.SimulationMetrics`."
  defdelegate target_tick_rate_hz(), to: SimulationMetrics
end
