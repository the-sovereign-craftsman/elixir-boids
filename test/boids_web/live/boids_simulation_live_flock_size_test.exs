defmodule BoidsWeb.BoidsSimulationLiveFlockSizeTest do
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

  test "the flock size input starts at the current count", %{conn: conn} do
    Boids.spawn_boids(12)

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s{#flock-size-form input[type=number][value="12"]})
  end

  test "applying a larger flock size spawns boids up to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    set_flock_size_from_page(view, "25")

    assert Boids.boid_count() == 25
    assert has_element?(view, "#boid-count", "25 / #{Boids.max_boid_count()}")
  end

  test "applying a smaller flock size removes boids, leaving no rows behind",
       %{conn: conn} do
    Boids.spawn_boids(30)
    {:ok, view, _html} = live(conn, ~p"/")

    set_flock_size_from_page(view, "10")

    assert Boids.boid_count() == 10
    assert has_element?(view, "#boid-count", "10 / #{Boids.max_boid_count()}")
    assert length(boid_rows()) == 10
  end

  test "a flock size past the limit applies the limit, and says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    set_flock_size_from_page(view, "#{Boids.max_boid_count() + 1}")

    assert Boids.boid_count() == Boids.max_boid_count()
    assert has_element?(view, "#flash-info", "limited to #{Boids.max_boid_count()} boids")
  end

  test "Clear all boids removes every boid and its row", %{conn: conn} do
    Boids.spawn_boids(15)
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#clear-boids-button") |> render_click()

    assert Boids.boid_count() == 0
    assert boid_rows() == []
    assert has_element?(view, "#boid-count", "0 / #{Boids.max_boid_count()}")
  end

  test "rejects a flock size that isn't a whole number of 0 or more, without changing the flock",
       %{conn: conn} do
    Boids.spawn_boids(5)
    {:ok, view, _html} = live(conn, ~p"/")

    for bad_count <- ["-5", "2.5", "lots", ""] do
      set_flock_size_from_page(view, bad_count)

      assert has_element?(view, "#flash-error", "Enter a whole number")
    end

    assert Boids.boid_count() == 5
  end

  test "the count picks up boids spawned outside the page, like from iex", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    Boids.spawn_boids(7)

    # The count refreshes on every frame; trigger one instead of waiting for the timer.
    send(view.pid, :render_frame)

    assert has_element?(view, "#boid-count", "7 / #{Boids.max_boid_count()}")
  end

  defp set_flock_size_from_page(view, count) do
    view
    |> form("#flock-size-form", flock_size: %{count: count})
    |> render_submit()
  end

  # Every row in the positions table belongs to a live boid in these tests.
  defp boid_rows, do: :ets.tab2list(BoidPositions.table_name())

  defp stop_all_boids, do: Boids.remove_all_boids()
end
