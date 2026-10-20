defmodule Boids.BoidPositionsSupervisor do
  @moduledoc """
  Supervises the positions table owner and the janitor that cleans up the table,
  with the `:rest_for_one` strategy.

  The janitor depends on the table: it deletes dead boids' rows from it. When the
  owner dies, the table is deleted with it, and a janitor cleaning up at that moment
  crashes. Worse, the app's `:one_for_one` supervisor would restart that janitor with
  no monitors, so no boid would be watched any more, while everything looked fine.

  `:rest_for_one` restarts every child started after the one that died. So when the
  owner dies, the janitor is restarted with it, in order: first a new owner with a
  new table, then a new janitor, which adopts every boid already running (see
  `Boids.BoidJanitor`). When the janitor dies on its own, the table is left alone.

  The boid supervisor is deliberately not in this group. A restarted
  `DynamicSupervisor` comes back empty, so restarting it would wipe out the flock.
  The boids don't need it either: they rewrite their rows into the new table on
  their next tick.
  """

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      Boids.BoidPositions,
      # After the owner, so it is restarted whenever the owner is.
      Boids.BoidJanitor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
