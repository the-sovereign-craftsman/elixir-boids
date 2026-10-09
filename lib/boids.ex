defmodule Boids do
  @moduledoc """
  Boids keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @spec spawn_boid() :: :ignore | {:error, any()} | pid()
  def spawn_boid() do
    {:ok, pid} = DynamicSupervisor.start_child(Boids.DynamicSupervisor, Boids.Boid)
    pid
  end

  @spec spawn_boids(non_neg_integer()) :: [pid()]
  def spawn_boids(count) do
    Enum.map(1..count, fn _ -> spawn_boid() end)
  end
end
