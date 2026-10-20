defmodule BoidsWeb.BoidsSimulationLiveFlockingControlsTest do
  # Not async: these tests change the app-wide flocking rule toggles.
  use BoidsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Boids.BoidFlockingRuleToggles

  setup do
    Boids.update_all_flocking_rule_toggles(false)
    on_exit(fn -> Boids.update_all_flocking_rule_toggles(false) end)
    :ok
  end

  describe "layout" do
    test "puts the flocking controls left of the canvas, with a panel reserved on the right",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#flocking-controls + #boid-canvas + #telemetry-panel")
    end
  end

  describe "rule toggles" do
    test "renders a toggle for every rule, off when the rule is off", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for rule <- ~w(separation cohesion alignment) do
        assert has_element?(view, toggle_selector(rule))
        refute has_element?(view, toggle_selector(rule) <> "[checked]")
      end
    end

    test "shows a rule that is already on as checked when the page loads", %{conn: conn} do
      Boids.update_flocking_rule_toggles(:cohesion, true)

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, toggle_selector("cohesion") <> "[checked]")
      refute has_element?(view, toggle_selector("separation") <> "[checked]")
    end

    test "turning a toggle on turns the rule on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      change_toggles(view, %{separation: "false", cohesion: "true", alignment: "false"})

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: false, cohesion: true, alignment: false}
    end

    test "turning a toggle off turns the rule off", %{conn: conn} do
      Boids.update_all_flocking_rule_toggles(true)
      {:ok, view, _html} = live(conn, ~p"/")

      change_toggles(view, %{separation: "true", cohesion: "true", alignment: "false"})

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: false}
    end

    test "the toggle shows as checked once the change is made", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      change_toggles(view, %{separation: "true", cohesion: "false", alignment: "false"})

      # render/1 waits for the LiveView to handle the broadcast that follows the change.
      render(view)
      assert has_element?(view, toggle_selector("separation") <> "[checked]")
    end

    test "a change made outside the page, like from iex, shows up on the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      Boids.update_flocking_rule_toggles(:alignment, true)

      render(view)
      assert has_element?(view, toggle_selector("alignment") <> "[checked]")
    end
  end

  describe "all on and all off buttons" do
    test "All on turns every rule on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#enable-all-flocking-rules") |> render_click()

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: true}

      render(view)

      for rule <- ~w(separation cohesion alignment) do
        assert has_element?(view, toggle_selector(rule) <> "[checked]")
      end
    end

    test "All off turns every rule off", %{conn: conn} do
      Boids.update_all_flocking_rule_toggles(true)
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#disable-all-flocking-rules") |> render_click()

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: false, cohesion: false, alignment: false}
    end
  end

  defp toggle_selector(rule), do: "#flocking-rule-toggles-form input[type=checkbox][id$=#{rule}]"

  defp change_toggles(view, toggle_params) do
    view
    |> form("#flocking-rule-toggles-form", flocking_rule_toggles: toggle_params)
    |> render_change()
  end
end
