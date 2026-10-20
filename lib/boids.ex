defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Boids.BoidFlockingRuleToggles
  alias Boids.BoidPositions

  # The most boids the UI will spawn. spawn_boids/1 ignores it, so iex can go past it
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

  @doc "The most boids `spawn_boids_up_to_limit/1` will let exist at once."
  @spec max_boid_count() :: pos_integer()
  def max_boid_count, do: @max_boid_count

  @doc "How many boid processes are alive right now."
  @spec boid_count() :: non_neg_integer()
  def boid_count do
    DynamicSupervisor.count_children(Boids.DynamicSupervisor).active
  end

  @doc """
  Spawns up to `requested_count` boids, but never more than would take the total
  past `max_boid_count/0`. Returns how many were actually spawned.
  """
  @spec spawn_boids_up_to_limit(non_neg_integer()) :: non_neg_integer()
  def spawn_boids_up_to_limit(requested_count)
      when is_integer(requested_count) and requested_count >= 0 do
    room_left = max(@max_boid_count - boid_count(), 0)
    count_to_spawn = min(requested_count, room_left)

    spawn_boids(count_to_spawn)
    count_to_spawn
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
end
