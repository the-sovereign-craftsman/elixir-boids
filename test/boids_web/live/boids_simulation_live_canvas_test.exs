defmodule BoidsWeb.BoidsSimulationLiveCanvasTest do
  # Not async: these tests insert rows into the app-wide positions table, which other
  # tests read for neighbor lookups.
  use BoidsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Boids.Boid
  alias Boids.BoidPositions

  # Each canvas point is [x, y, newness]. Newness is 1.0 for a boid spawned this
  # instant, falls to 0.0 over its first moments, and is 0.0 from then on, so the canvas
  # can draw boids that just replaced killed ones in a fading highlight.

  test "a boid spawned just now is sent with a newness near 1.0", %{conn: conn} do
    insert_boid_row({111.0, 222.0}, System.monotonic_time(:millisecond))
    {:ok, view, _html} = live(conn, ~p"/")

    [_x, _y, newness] = pushed_point_at(view, 111.0, 222.0)

    assert newness > 0.8
  end

  test "a boid spawned long ago is sent with a newness of 0.0", %{conn: conn} do
    insert_boid_row({333.0, 444.0}, System.monotonic_time(:millisecond) - 60_000)
    {:ok, view, _html} = live(conn, ~p"/")

    assert pushed_point_at(view, 333.0, 444.0) == [333.0, 444.0, 0.0]
  end

  test "a boid with no spawn time is sent with a newness of 0.0", %{conn: conn} do
    insert_boid_row({555.0, 666.0}, nil)
    {:ok, view, _html} = live(conn, ~p"/")

    assert pushed_point_at(view, 555.0, 666.0) == [555.0, 666.0, 0.0]
  end

  defp insert_boid_row({x, y} = position, spawned_at_ms) do
    key = {0, 0, make_ref()}
    boid = %Boid{position: position, velocity: {0.0, 0.0}, spawned_at_ms: spawned_at_ms}

    :ets.insert(BoidPositions.table_name(), {key, boid})
    on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

    {x, y}
  end

  # Waits for the next frame and returns the point drawn at {x, y}.
  defp pushed_point_at(view, x, y) do
    assert_push_event(view, "update_boid_positions", %{positions: positions}, 500)
    Enum.find(positions, fn [point_x, point_y, _newness] -> point_x == x and point_y == y end)
  end
end
