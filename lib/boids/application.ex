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
      {DynamicSupervisor, name: Boids.DynamicSupervisor, strategy: :one_for_one},
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
