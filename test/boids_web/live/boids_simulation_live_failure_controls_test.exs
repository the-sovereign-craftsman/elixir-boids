defmodule BoidsWeb.BoidsSimulationLiveFailureControlsTest do
  # Not async: these tests start and kill real boids under the app's one DynamicSupervisor.
  use BoidsWeb.ConnCase, async: false

  import Boids.AssertEventually
  import Boids.FlockTestHelpers
  import Mox
  import Phoenix.LiveViewTest

  # The boids are started by the DynamicSupervisor, not this test process, so the mock
  # has to be global. stub_with/2 makes it behave like the real Boids.Boid.
  setup :set_mox_global

  setup do
    stub_with(Boids.BoidMock, Boids.Boid)
    on_exit(&Boids.remove_all_boids/0)
    :ok
  end

  test "the Break things card sits under the flocking rules", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#flocking-controls + #failure-controls")
  end

  test "the kill count starts at 100", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#kill-boids-form input[type='number'][value='100']")
  end

  test "submitting the form kills that many boids, and they come back", %{conn: conn} do
    Boids.spawn_boids(5)
    pids_before_kill = running_boid_pids()
    crash_count_before = Boids.boid_crash_count()
    {:ok, view, _html} = live(conn, ~p"/")

    html = kill_boids(view, "2")

    assert html =~ "Killed 2 boids."
    assert_killed_boids_replaced(pids_before_kill, 2)
    assert_eventually(fn -> Boids.boid_crash_count() == crash_count_before + 2 end)
  end

  test "rejects 0 and kills nothing", %{conn: conn} do
    Boids.spawn_boids(2)
    crash_count_before = Boids.boid_crash_count()
    {:ok, view, _html} = live(conn, ~p"/")

    assert kill_boids(view, "0") =~ "Enter a whole number of boids, 1 or more."
    assert Boids.boid_crash_count() == crash_count_before
  end

  test "rejects input that isn't a whole number", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert kill_boids(view, "abc") =~ "Enter a whole number of boids, 1 or more."
  end

  defp kill_boids(view, count) do
    view
    |> form("#kill-boids-form", kill_boids: %{count: count})
    |> render_submit()
  end
end
