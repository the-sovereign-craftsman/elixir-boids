defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Boids.BoidFlockingRuleToggles
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
    Boids.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.take(count)
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      DynamicSupervisor.terminate_child(Boids.DynamicSupervisor, pid)
    end)
  end

  @doc "Stops every boid."
  @spec remove_all_boids() :: :ok
  def remove_all_boids, do: remove_boids(boid_count())

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
