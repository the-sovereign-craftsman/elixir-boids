defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Boids.BoidFlockingRuleToggles
  alias Boids.BoidPositions

  @spec spawn_boid() :: pid()
  def spawn_boid do
    {:ok, pid} = DynamicSupervisor.start_child(Boids.DynamicSupervisor, Boids.BoidServer)
    pid
  end

  @spec spawn_boids(non_neg_integer()) :: [pid()]
  def spawn_boids(count) do
    Enum.map(1..count, fn _ -> spawn_boid() end)
  end

  @spec list_boid_positions() :: [{pid(), Boids.Boid.t()}]
  def list_boid_positions do
    :ets.tab2list(BoidPositions.table_name())
  end

  @doc "Turns one flocking rule on or off. See `Boids.BoidFlockingRuleToggles`."
  defdelegate update_flocking_rule_toggles(rule, enabled?), to: BoidFlockingRuleToggles
end
