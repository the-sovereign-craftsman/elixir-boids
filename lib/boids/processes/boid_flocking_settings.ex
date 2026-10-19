defmodule Boids.BoidFlockingSettings do
  @moduledoc """
  Owns the `:boid_flocking_settings` ETS table, which records which flocking
  rules are currently turned on.

  The table holds a single row, `{:enabled_flocking_rules, %{separation: _,
  cohesion: _, alignment: _}}`. Every rule starts turned off. Keeping all the
  rules in one row means a reader always sees a consistent set of rules, never
  one rule from before a change and another from after.

  The table is `:protected`: any process can read it, but only this process can
  write to it. Changes go through `update_flocking_settings/2`, which sends a
  `GenServer.call` so they are applied one at a time. Reads go straight to ETS,
  so boids never wait on this process.
  """

  use GenServer

  @table_name :boid_flocking_settings
  @enabled_flocking_rules_key :enabled_flocking_rules
  @flocking_rules [:separation, :cohesion, :alignment]

  @typedoc "A key for the table's only row. It is always this atom."
  @type row_key :: :enabled_flocking_rules

  @typedoc "A flocking rule that can be turned on or off."
  @type flocking_rule :: :separation | :cohesion | :alignment

  @typedoc "Whether each flocking rule is on."
  @type enabled_flocking_rules :: %{
          separation: boolean(),
          cohesion: boolean(),
          alignment: boolean()
        }

  @typedoc "The table's only row."
  @type row :: {row_key(), enabled_flocking_rules()}

  def table_name, do: @table_name

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Turns one flocking rule on or off.

  Only accepts a known rule and a boolean. Anything else raises
  `FunctionClauseError` here, in the caller, before reaching this process.
  """
  @spec update_flocking_settings(flocking_rule(), boolean()) :: :ok
  def update_flocking_settings(rule, enabled?)
      when rule in @flocking_rules and is_boolean(enabled?) do
    GenServer.call(__MODULE__, {:set_flocking_rule_enabled, rule, enabled?})
  end

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])

    :ets.insert(
      @table_name,
      {@enabled_flocking_rules_key, %{separation: false, cohesion: false, alignment: false}}
    )

    {:ok, @table_name}
  end

  @impl true
  def handle_call({:set_flocking_rule_enabled, rule, enabled?}, _from, state) do
    [{@enabled_flocking_rules_key, enabled_flocking_rules}] =
      :ets.lookup(@table_name, @enabled_flocking_rules_key)

    updated_flocking_rules = Map.put(enabled_flocking_rules, rule, enabled?)

    :ets.insert(@table_name, {@enabled_flocking_rules_key, updated_flocking_rules})

    {:reply, :ok, state}
  end
end
