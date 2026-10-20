defmodule Boids.BoidBehaviour do
  @moduledoc """
  The contract `Boids.BoidServer` relies on for creating and advancing a boid.

  `Boids.Boid` is the real implementation. Tests replace it with
  `Boids.BoidMock` (Mox) via the `:boid_module` config, so server behaviour
  can be tested without random positions.
  """

  alias Boids.Boid
  alias Boids.BoidFlockingRuleToggles

  @callback new() :: Boid.t()

  @callback advance_boid(
              Boid.t(),
              [Boid.t()],
              BoidFlockingRuleToggles.enabled_flocking_rules()
            ) :: Boid.t()
end
