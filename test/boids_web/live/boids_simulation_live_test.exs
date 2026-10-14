defmodule BoidsWeb.BoidsSimulationLiveTest do
  use BoidsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Boids.Boid
  alias Boids.BoidPositions

  describe "mount" do
    test "renders the canvas wired to the hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "canvas#boid-canvas[phx-hook][phx-update=ignore]")
    end
  end

  describe "handle_info/2 :render_frame" do
    test "pushes boid positions from the table as [x, y] lists", %{conn: conn} do
      # Real row shape; a ref stands in for the pid so the key is unique in the shared table.
      key = {0, 0, make_ref()}
      boid = %Boid{position: {12.0, 34.0}, velocity: {1.0, 1.0}}

      :ets.insert(BoidPositions.table_name(), {key, boid})
      on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

      {:ok, view, _html} = live(conn, ~p"/")

      assert_push_event(view, "update_boid_positions", %{positions: positions})
      assert [12.0, 34.0] in positions
    end

    test "keeps pushing frames after the first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert_push_event(view, "update_boid_positions", _)
      assert_push_event(view, "update_boid_positions", _)
    end
  end
end
