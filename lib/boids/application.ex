defmodule Boids.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BoidsWeb.Telemetry,
      Boids.Repo,
      {DNSCluster, query: Application.get_env(:boids, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Boids.PubSub},
      Boids.BoidPositions,
      # Before the boids, so the toggles table exists before any boid ticks.
      Boids.BoidFlockingRuleToggles,
      # Before the boids, which register with it as they start.
      Boids.BoidJanitor,
      # The default limit is 3 restarts in 5 seconds. Past it the supervisor gives up
      # and stops every boid, so killing even a handful at once would end the whole
      # flock. The failure demos kill hundreds, so the limit is raised far past that.
      {DynamicSupervisor,
       name: Boids.DynamicSupervisor, strategy: :one_for_one, max_restarts: 10_000, max_seconds: 1},
      # Holds the CPU hogs for the fair-scheduling demo, kept apart from the boids.
      {DynamicSupervisor, name: Boids.CpuHogSupervisor, strategy: :one_for_one},
      # After the boid supervisor, because each sample counts its children. No boid
      # starts at boot, so the tick counter still exists before any boid ticks.
      Boids.SimulationMetrics,
      # Start a worker by calling: Boids.Worker.start_link(arg)
      # {Boids.Worker, arg},
      # Start to serve requests, typically the last entry
      BoidsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Boids.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BoidsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
