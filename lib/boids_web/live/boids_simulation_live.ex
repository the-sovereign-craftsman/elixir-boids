defmodule BoidsWeb.BoidsSimulationLive do
  use BoidsWeb, :live_view

  import BoidsWeb.SimulationDashboardComponents

  alias Boids.Boid

  @frame_interval_ms div(1000, 24)
  # How long a newly spawned boid stays highlighted on the canvas.
  @new_boid_highlight_ms 1500

  # Shown beside each toggle, in this order.
  @flocking_rule_descriptions [
    separation: "Steer away from neighbors that are too close.",
    cohesion: "Steer toward the center of nearby boids.",
    alignment: "Match the heading of nearby boids."
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Boids.subscribe_to_flocking_rule_toggles()
      Boids.subscribe_to_simulation_metrics()
      Process.send_after(self(), :render_frame, @frame_interval_ms)
    end

    {:ok,
     socket
     # The dashboard shows a placeholder until the first metrics broadcast, within a second.
     |> assign(:simulation_metrics_snapshot, nil)
     |> assign(:simulation_metrics_history, [])
     |> assign(:target_tick_rate_hz, Boids.target_tick_rate_hz())
     |> assign(:flocking_rule_descriptions, @flocking_rule_descriptions)
     |> assign_flocking_rule_toggles_form(Boids.flocking_rule_toggles())
     |> assign(:kill_boids_form, to_form(%{"count" => 100}, as: :kill_boids))
     |> assign(:crash_boids_form, to_form(%{"count" => 100}, as: :crash_boids))
     |> assign(:cpu_hog_count, Boids.cpu_hog_count())
     |> assign(:max_boid_count, Boids.max_boid_count())
     |> assign_boid_count(Boids.boid_count())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <%!-- Controls beside the canvas from md up; the telemetry column joins at xl. --%>
      <div class="grid items-start gap-6 md:grid-cols-[16rem_minmax(0,1fr)] xl:grid-cols-[16rem_minmax(0,1fr)_16rem]">
        <div id="simulation-controls" class="flex flex-col gap-6">
          <section id="flock-size-controls" class="card bg-base-200">
            <div class="card-body gap-4">
              <h2 class="card-title">Boids</h2>
              <p id="boid-count" class="text-sm">{@boid_count} / {@max_boid_count}</p>

              <.form for={@flock_size_form} id="flock-size-form" phx-submit="set_flock_size">
                <.input
                  field={@flock_size_form[:count]}
                  type="number"
                  label="Flock size"
                  min="0"
                  max={@max_boid_count}
                />
                <.button id="set-flock-size-button" class="btn btn-sm btn-primary">
                  Apply
                </.button>
              </.form>

              <.button id="clear-boids-button" class="btn btn-sm btn-soft" phx-click="clear_boids">
                Clear all boids
              </.button>
            </div>
          </section>

          <section id="flocking-controls" class="card bg-base-200">
            <div class="card-body gap-4">
              <h2 class="card-title">Flocking rules</h2>

              <.form
                for={@flocking_rule_toggles_form}
                id="flocking-rule-toggles-form"
                phx-change="update_flocking_rule_toggles"
              >
                <div :for={{rule, description} <- @flocking_rule_descriptions} class="mb-3">
                  <.input
                    field={@flocking_rule_toggles_form[rule]}
                    type="checkbox"
                    label={rule |> Atom.to_string() |> String.capitalize()}
                    class="toggle toggle-primary toggle-sm mr-2"
                  />
                  <p class="text-xs text-base-content/70">{description}</p>
                </div>
              </.form>

              <div class="flex gap-2">
                <.button
                  id="enable-all-flocking-rules"
                  class="btn btn-sm btn-primary btn-soft"
                  phx-click="update_all_flocking_rule_toggles"
                  phx-value-enabled="true"
                >
                  All on
                </.button>
                <.button
                  id="disable-all-flocking-rules"
                  class="btn btn-sm btn-soft"
                  phx-click="update_all_flocking_rule_toggles"
                  phx-value-enabled="false"
                >
                  All off
                </.button>
              </div>
            </div>
          </section>
        </div>

        <%!-- The canvas with the failure controls under it, next to what they break. --%>
        <div id="canvas-column" class="flex flex-col gap-6">
          <canvas
            id="boid-canvas"
            phx-hook=".BoidCanvas"
            phx-update="ignore"
            width="1000"
            height="1000"
            class="w-full aspect-square border border-base-300"
          ></canvas>

          <section id="failure-controls" class="card bg-base-200">
            <div class="card-body gap-4">
              <h2 class="card-title">Break things</h2>

              <div class="grid gap-6 lg:grid-cols-3">
                <div id="kill-boids-controls" class="flex flex-col gap-2">
                  <p class="text-xs text-base-content/70">
                    Kill random boid processes. Their supervisor replaces each one within
                    milliseconds. The new boids flash red.
                  </p>
                  <.form for={@kill_boids_form} id="kill-boids-form" phx-submit="kill_boids">
                    <.input
                      field={@kill_boids_form[:count]}
                      type="number"
                      label="Boids to kill"
                      min="1"
                    />
                    <.button id="kill-boids-button" class="btn btn-sm btn-error">Kill</.button>
                  </.form>
                </div>

                <div id="crash-boids-controls" class="flex flex-col gap-2">
                  <p class="text-xs text-base-content/70">
                    Corrupt boids' state, so their own code crashes on the next tick.
                  </p>
                  <.form for={@crash_boids_form} id="crash-boids-form" phx-submit="crash_boids">
                    <.input
                      field={@crash_boids_form[:count]}
                      type="number"
                      label="Boids to crash"
                      min="1"
                    />
                    <.button id="crash-boids-button" class="btn btn-sm btn-warning">Crash</.button>
                  </.form>
                </div>

                <div id="cpu-hog-controls" class="flex flex-col gap-2">
                  <p class="text-xs text-base-content/70">
                    Start processes that spin forever. The BEAM still gives every boid its turn.
                  </p>
                  <p class="text-sm">CPU hogs: <span id="cpu-hog-count">{@cpu_hog_count}</span></p>
                  <div class="flex flex-wrap gap-2">
                    <.button
                      id="start-cpu-hog-button"
                      class="btn btn-sm btn-warning btn-soft"
                      phx-click="start_cpu_hog"
                    >
                      + Hog
                    </.button>
                    <.button
                      id="start-cpu-hog-per-core-button"
                      class="btn btn-sm btn-warning btn-soft"
                      phx-click="start_cpu_hog_per_core"
                    >
                      One per core
                    </.button>
                    <.button
                      id="stop-cpu-hogs-button"
                      class="btn btn-sm btn-soft"
                      phx-click="stop_cpu_hogs"
                    >
                      Stop all
                    </.button>
                  </div>
                </div>
              </div>

              <div class="border-t border-base-300 pt-4">
                <.button
                  id="kill-boid-positions-owner-button"
                  class="btn btn-sm btn-error btn-outline"
                  phx-click="kill_boid_positions_owner"
                  data-confirm="This kills the process that owns the positions table. Continue?"
                >
                  Kill the positions table owner
                </.button>
              </div>
            </div>
          </section>
        </div>

        <%!-- Under the canvas, across both columns, until xl gives it the right column. --%>
        <aside id="telemetry-panel" class="md:col-span-2 xl:col-span-1">
          <.simulation_dashboard
            snapshot={@simulation_metrics_snapshot}
            history={@simulation_metrics_history}
            target_tick_rate_hz={@target_tick_rate_hz}
          />
        </aside>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".BoidCanvas">
        export default {
          mounted() {
            const ctx = this.el.getContext("2d")
            const size = 4

            // Each position is [x, y, newness]. Every boid is drawn blue, then boids
            // spawned in the last moments are drawn again in red on top, fading out as
            // newness falls from 1 to 0. That's how replaced boids show up after a kill.
            this.handleEvent("update_boid_positions", ({positions}) => {
              ctx.clearRect(0, 0, this.el.width, this.el.height)
              ctx.fillStyle = "#3b82f6"

              for (const [x, y] of positions) {
                ctx.fillRect(x - size / 2, y - size / 2, size, size)
              }

              ctx.fillStyle = "#ef4444"

              for (const [x, y, newness] of positions) {
                if (newness > 0) {
                  ctx.globalAlpha = newness
                  ctx.fillRect(x - size / 2, y - size / 2, size, size)
                }
              }

              ctx.globalAlpha = 1
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  # Only writes the change. The switches re-render when the broadcast comes back
  # (handle_info/2 below), the same way they do for a change made from iex. The toggles
  # never allow cohesion or alignment without separation, so the result can differ from
  # what was asked for; the flash explains when it does.
  @impl true
  def handle_event(
        "update_flocking_rule_toggles",
        %{"flocking_rule_toggles" => toggle_params},
        socket
      ) do
    current_flocking_rule_toggles = Boids.flocking_rule_toggles()

    requested_flocking_rule_toggles =
      Map.new(@flocking_rule_descriptions, fn {rule, _description} ->
        {rule, Map.get(toggle_params, Atom.to_string(rule)) == "true"}
      end)

    for {rule, enabled?} <- requested_flocking_rule_toggles,
        enabled? != Map.fetch!(current_flocking_rule_toggles, rule) do
      Boids.update_flocking_rule_toggles(rule, enabled?)
    end

    {:noreply,
     put_collapse_guard_flash(
       socket,
       requested_flocking_rule_toggles,
       Boids.flocking_rule_toggles()
     )}
  end

  def handle_event("set_flock_size", %{"flock_size" => %{"count" => count}}, socket) do
    case Integer.parse(count) do
      {target_count, ""} when target_count >= 0 ->
        new_count = Boids.set_boid_count(target_count)

        {:noreply,
         socket
         |> assign_boid_count(new_count)
         |> put_limit_flash(target_count)}

      _not_a_whole_number ->
        {:noreply, put_flash(socket, :error, "Enter a whole number of boids, 0 or more.")}
    end
  end

  def handle_event("clear_boids", _params, socket) do
    Boids.remove_all_boids()

    {:noreply, assign_boid_count(socket, Boids.boid_count())}
  end

  def handle_event("kill_boids", %{"kill_boids" => %{"count" => count}}, socket) do
    case Integer.parse(count) do
      {kill_count, ""} when kill_count >= 1 ->
        killed_count = Boids.kill_boids(kill_count)

        {:noreply,
         socket
         |> assign(:kill_boids_form, to_form(%{"count" => kill_count}, as: :kill_boids))
         |> put_flash(:info, "Killed #{killed_count} boids.")}

      _not_a_whole_number ->
        {:noreply, put_flash(socket, :error, "Enter a whole number of boids, 1 or more.")}
    end
  end

  def handle_event("crash_boids", %{"crash_boids" => %{"count" => count}}, socket) do
    case Integer.parse(count) do
      {crash_count, ""} when crash_count >= 1 ->
        corrupted_count = Boids.crash_boids(crash_count)

        {:noreply,
         socket
         |> assign(:crash_boids_form, to_form(%{"count" => crash_count}, as: :crash_boids))
         |> put_flash(
           :info,
           "Corrupted #{corrupted_count} boids. They crash on their next tick."
         )}

      _not_a_whole_number ->
        {:noreply, put_flash(socket, :error, "Enter a whole number of boids, 1 or more.")}
    end
  end

  def handle_event("kill_boid_positions_owner", _params, socket) do
    Boids.kill_boid_positions_owner()

    {:noreply, socket}
  end

  def handle_event("start_cpu_hog", _params, socket) do
    Boids.start_cpu_hog()

    {:noreply, assign(socket, :cpu_hog_count, Boids.cpu_hog_count())}
  end

  # One hog per scheduler. The BEAM runs one scheduler per CPU core, so this keeps every
  # core busy with hogs, and the boids have to share every core with them.
  def handle_event("start_cpu_hog_per_core", _params, socket) do
    Boids.start_cpu_hogs(:erlang.system_info(:schedulers_online))

    {:noreply, assign(socket, :cpu_hog_count, Boids.cpu_hog_count())}
  end

  def handle_event("stop_cpu_hogs", _params, socket) do
    Boids.stop_cpu_hogs()

    {:noreply, assign(socket, :cpu_hog_count, Boids.cpu_hog_count())}
  end

  def handle_event("update_all_flocking_rule_toggles", %{"enabled" => enabled}, socket) do
    Boids.update_all_flocking_rule_toggles(enabled == "true")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:flocking_rule_toggles_updated, flocking_rule_toggles}, socket) do
    {:noreply, assign_flocking_rule_toggles_form(socket, flocking_rule_toggles)}
  end

  def handle_info({:simulation_metrics_updated, snapshot, history}, socket) do
    {:noreply,
     socket
     |> assign(:simulation_metrics_snapshot, snapshot)
     |> assign(:simulation_metrics_history, history)
     # Hogs can also be started from iex, so the count is refreshed with the metrics.
     |> assign(:cpu_hog_count, Boids.cpu_hog_count())}
  end

  def handle_info(:render_frame, socket) do
    now_ms = System.monotonic_time(:millisecond)

    positions =
      Boids.list_boid_positions()
      |> Enum.map(fn {{_cell_x, _cell_y, _pid}, %Boid{position: {x, y}} = boid} ->
        [x, y, newness(boid, now_ms)]
      end)

    Process.send_after(self(), :render_frame, @frame_interval_ms)

    # Boids can also be spawned from iex, so the count is refreshed every frame. assign/3
    # only marks it changed when the number differs, so a steady count re-renders nothing.
    {:noreply,
     socket
     |> assign(:boid_count, Boids.boid_count())
     |> push_event("update_boid_positions", %{positions: positions})}
  end

  # 1.0 for a boid spawned this instant, falling to 0.0 over @new_boid_highlight_ms,
  # then 0.0. The canvas draws it as a red highlight that fades, so the boids that
  # replaced killed ones stand out. Rounded, because it's sent for every boid every frame.
  defp newness(%Boid{spawned_at_ms: nil}, _now_ms), do: 0.0

  defp newness(%Boid{spawned_at_ms: spawned_at_ms}, now_ms) do
    age_ms = now_ms - spawned_at_ms
    Float.round(max(1 - age_ms / @new_boid_highlight_ms, 0.0), 2)
  end

  # Cohesion or alignment without separation collapses the flock, so the toggles adjust
  # such a change (see Boids.BoidFlockingRuleToggles). Explains the adjustment when one
  # was made.
  defp put_collapse_guard_flash(socket, requested_toggles, resulting_toggles) do
    cond do
      not collapses_flock?(requested_toggles) ->
        socket

      resulting_toggles.separation ->
        put_flash(
          socket,
          :info,
          "Separation was turned on too: without it, cohesion and alignment pack the flock tighter and tighter until memory runs out."
        )

      true ->
        put_flash(
          socket,
          :info,
          "Cohesion and alignment were turned off too: without separation they pack the flock tighter and tighter until memory runs out."
        )
    end
  end

  defp collapses_flock?(toggles),
    do: (toggles.cohesion or toggles.alignment) and not toggles.separation

  defp put_limit_flash(socket, target_count) do
    max_boid_count = Boids.max_boid_count()

    if target_count > max_boid_count do
      put_flash(socket, :info, "The flock size is limited to #{max_boid_count} boids.")
    else
      socket
    end
  end

  # Also resets the flock size input to the real count, so it shows what was applied.
  defp assign_boid_count(socket, boid_count) do
    socket
    |> assign(:boid_count, boid_count)
    |> assign(:flock_size_form, to_form(%{"count" => boid_count}, as: :flock_size))
  end

  # Forms read their values like submitted params, which have string keys, so the
  # rule atoms (:cohesion) become strings ("cohesion") here.
  defp assign_flocking_rule_toggles_form(socket, flocking_rule_toggles) do
    toggle_params =
      Map.new(flocking_rule_toggles, fn {rule, enabled?} -> {Atom.to_string(rule), enabled?} end)

    assign(
      socket,
      :flocking_rule_toggles_form,
      to_form(toggle_params, as: :flocking_rule_toggles)
    )
  end
end
