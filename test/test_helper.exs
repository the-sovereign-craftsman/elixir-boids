ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Boids.Repo, :manual)

Mox.defmock(Boids.BoidMock, for: Boids.BoidBehaviour)
