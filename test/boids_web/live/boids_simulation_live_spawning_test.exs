defmodule BoidsWeb.BoidsSimulationLiveSpawningTest do
  # Not async: these tests start real boids under the app's one DynamicSupervisor.
  use BoidsWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias Boids.BoidPositions

  # The boids are started by the DynamicSupervisor, not this test process, so the mock
  # has to be global. stub_with/2 makes it behave like the real Boids.Boid.
  setup :set_mox_global

  setup do
    stub_with(Boids.BoidMock, Boids.Boid)
    on_exit(&stop_all_boids/0)
    :ok
  end

  test "shows how many boids are alive, out of the limit", %{conn: conn} do
    Boids.spawn_boids(3)

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#boid-count", "3 / #{Boids.max_boid_count()}")
  end

  test "spawning adds the requested number of boids and updates the count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    spawn_from_page(view, "25")

    assert Boids.boid_count() == 25
    assert has_element?(view, "#boid-count", "25 / #{Boids.max_boid_count()}")
  end

  test "a request past the limit spawns only up to it, and says so", %{conn: conn} do
    Boids.spawn_boids(Boids.max_boid_count() - 5)
    {:ok, view, _html} = live(conn, ~p"/")

    spawn_from_page(view, "100")

    assert Boids.boid_count() == Boids.max_boid_count()
    assert has_element?(view, "#flash-info", "Spawned 5 boids")
  end

  test "the spawn button is disabled once the limit is reached", %{conn: conn} do
    Boids.spawn_boids(Boids.max_boid_count())

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#spawn-boids-button[disabled]")
  end

  test "rejects a count that isn't a positive whole number, without spawning", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for bad_count <- ["0", "-5", "2.5", "lots", ""] do
      spawn_from_page(view, bad_count)

      assert has_element?(view, "#flash-error", "Enter a whole number")
    end

    assert Boids.boid_count() == 0
  end

  test "the count picks up boids spawned outside the page, like from iex", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    Boids.spawn_boids(7)

    # The count refreshes on every frame; trigger one instead of waiting for the timer.
    send(view.pid, :render_frame)

    assert has_element?(view, "#boid-count", "7 / #{Boids.max_boid_count()}")
  end

  defp spawn_from_page(view, count) do
    view
    |> form("#spawn-boids-form", spawn_boids: %{count: count})
    |> render_submit()
  end

  # Stops every boid and removes its row; rows aren't cleaned up on their own yet.
  defp stop_all_boids do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Boids.DynamicSupervisor) do
      DynamicSupervisor.terminate_child(Boids.DynamicSupervisor, pid)
      :ets.match_delete(BoidPositions.table_name(), {{:_, :_, pid}, :_})
    end
  end
end
