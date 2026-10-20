defmodule BoidsWeb.BoidsSimulationLiveDashboardTest do
  use BoidsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BoidsWeb.SimulationDashboardComponents

  # Every test sends its own snapshot straight to the LiveView, the same message the
  # metrics process broadcasts, so no test waits on the one-second sample timer.

  test "shows a placeholder before the first snapshot arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#telemetry-panel #simulation-dashboard", "Waiting for metrics")
  end

  test "renders a snapshot from a metrics broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send_snapshot(view, snapshot())

    assert has_element?(view, "#boid-process-count", "4,812")
    assert has_element?(view, "#total-process-count", "5,231")
    assert has_element?(view, "#tick-rate", "29.7")
    assert has_element?(view, "#restart-count", "0")
    assert has_element?(view, "#scheduler-utilization", "63%")
    assert has_element?(view, "#memory-usage", "182 MB")
    assert has_element?(view, "#memory-per-process", "2.8 KB")
  end

  test "renders one bar per scheduler", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send_snapshot(
      view,
      snapshot(scheduler_utilization_percent_by_scheduler: [10.0, 50.0, 90.0, 0.0])
    )

    assert has_element?(view, "#scheduler-bars > div:nth-child(4)")
    refute has_element?(view, "#scheduler-bars > div:nth-child(5)")
  end

  test "omits the target tick rate when ticks are sent by hand", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send_snapshot(view, snapshot())

    assert has_element?(view, "#tick-rate", "29.7")
    refute has_element?(view, "#tick-rate", "/")
  end

  describe "sparkline/1" do
    test "renders a line from a single value" do
      html = render_component(&SimulationDashboardComponents.sparkline/1, id: "one", values: [5])

      assert html =~ "<polyline"
    end

    test "renders a line when every value is zero" do
      html =
        render_component(&SimulationDashboardComponents.sparkline/1, id: "zeros", values: [0, 0])

      assert html =~ "<polyline"
      refute html =~ "NaN"
    end
  end

  defp send_snapshot(view, snapshot) do
    send(view.pid, {:simulation_metrics_updated, snapshot, [snapshot]})
    render(view)
  end

  defp snapshot(overrides \\ []) do
    Map.merge(
      %{
        boid_process_count: 4812,
        total_process_count: 5231,
        tick_rate_hz: 29.7,
        restart_count: 0,
        restarts_per_second: 0.0,
        scheduler_utilization_percent: 63.0,
        scheduler_utilization_percent_by_scheduler: [60.0, 66.0],
        total_memory_bytes: 182_000_000,
        memory_per_boid_bytes: 2_800
      },
      Map.new(overrides)
    )
  end
end
