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

  test "the Break things card sits under the canvas, with kill, crash and hogs side by side",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#canvas-column > #boid-canvas + #failure-controls")

    assert has_element?(
             view,
             "#failure-controls #kill-boids-controls + #crash-boids-controls + #cpu-hog-controls"
           )
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

  describe "crash control" do
    test "the crash count starts at 100", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#crash-boids-form input[type='number'][value='100']")
    end

    test "submitting the form corrupts that many boids", %{conn: conn} do
      Boids.spawn_boids(4)
      {:ok, view, _html} = live(conn, ~p"/")

      html = crash_boids(view, "3")

      assert html =~ "Corrupted 3 boids. They crash on their next tick."

      corrupted_count =
        Enum.count(running_boid_pids(), &match?(%{velocity: :corrupted}, :sys.get_state(&1)))

      assert corrupted_count == 3
    end

    test "rejects 0 and input that isn't a whole number", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert crash_boids(view, "0") =~ "Enter a whole number of boids, 1 or more."
      assert crash_boids(view, "abc") =~ "Enter a whole number of boids, 1 or more."
    end
  end

  describe "CPU hog controls" do
    setup do
      on_exit(&Boids.stop_cpu_hogs/0)
      :ok
    end

    test "shows how many hogs are running, starting at 0", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#cpu-hog-count", "0")
    end

    test "+ Hog starts one hog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#start-cpu-hog-button") |> render_click()

      assert Boids.cpu_hog_count() == 1
      assert has_element?(view, "#cpu-hog-count", "1")
    end

    test "One per core starts a hog for every scheduler", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      scheduler_count = :erlang.system_info(:schedulers_online)

      view |> element("#start-cpu-hog-per-core-button") |> render_click()

      assert Boids.cpu_hog_count() == scheduler_count
      assert has_element?(view, "#cpu-hog-count", "#{scheduler_count}")
    end

    test "Stop all stops every hog", %{conn: conn} do
      Boids.start_cpu_hogs(2)
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#stop-cpu-hogs-button") |> render_click()

      assert Boids.cpu_hog_count() == 0
      assert has_element?(view, "#cpu-hog-count", "0")
    end
  end

  defp crash_boids(view, count) do
    view
    |> form("#crash-boids-form", crash_boids: %{count: count})
    |> render_submit()
  end

  defp kill_boids(view, count) do
    view
    |> form("#kill-boids-form", kill_boids: %{count: count})
    |> render_submit()
  end
end
