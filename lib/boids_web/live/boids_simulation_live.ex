defmodule BoidsWeb.BoidsSimulationLive do
  use BoidsWeb, :live_view

  alias Boids.Boid

  @frame_interval_ms div(1000, 24)
  @default_spawn_count "500"

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
      Process.send_after(self(), :render_frame, @frame_interval_ms)
    end

    {:ok,
     socket
     |> assign(:flocking_rule_descriptions, @flocking_rule_descriptions)
     |> assign_flocking_rule_toggles_form(Boids.flocking_rule_toggles())
     |> assign(:boid_count, Boids.boid_count())
     |> assign(:max_boid_count, Boids.max_boid_count())
     |> assign(:spawn_boids_form, to_form(%{"count" => @default_spawn_count}, as: :spawn_boids))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <%!-- Controls beside the canvas from md up; the telemetry column joins at xl. --%>
      <div class="grid items-start gap-6 md:grid-cols-[16rem_minmax(0,1fr)] xl:grid-cols-[16rem_minmax(0,1fr)_16rem]">
        <div id="simulation-controls" class="flex flex-col gap-6">
          <section id="boid-spawning" class="card bg-base-200">
            <div class="card-body gap-4">
              <h2 class="card-title">Boids</h2>
              <p id="boid-count" class="text-sm">{@boid_count} / {@max_boid_count}</p>

              <.form for={@spawn_boids_form} id="spawn-boids-form" phx-submit="spawn_boids">
                <.input
                  field={@spawn_boids_form[:count]}
                  type="number"
                  label="How many to spawn"
                  min="1"
                  max={@max_boid_count}
                />
                <.button
                  id="spawn-boids-button"
                  class="btn btn-sm btn-primary"
                  disabled={@boid_count >= @max_boid_count}
                >
                  Spawn
                </.button>
              </.form>
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

        <canvas
          id="boid-canvas"
          phx-hook=".BoidCanvas"
          phx-update="ignore"
          width="1000"
          height="1000"
          class="w-full aspect-square border border-base-300"
        ></canvas>

        <%!-- Reserved for the telemetry dashboard, so the canvas stays centered. --%>
        <aside id="telemetry-panel" class="hidden xl:block"></aside>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".BoidCanvas">
        export default {
          mounted() {
            const ctx = this.el.getContext("2d")
            const size = 4

            this.handleEvent("update_boid_positions", ({positions}) => {
              ctx.clearRect(0, 0, this.el.width, this.el.height)
              ctx.fillStyle = "#3b82f6"

              for (const [x, y] of positions) {
                ctx.fillRect(x - size / 2, y - size / 2, size, size)
              }
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  # Only writes the change. The switches re-render when the broadcast comes back
  # (handle_info/2 below), the same way they do for a change made from iex.
  @impl true
  def handle_event(
        "update_flocking_rule_toggles",
        %{"flocking_rule_toggles" => toggle_params},
        socket
      ) do
    current_flocking_rule_toggles = Boids.flocking_rule_toggles()

    for {rule, _description} <- @flocking_rule_descriptions do
      enabled? = Map.get(toggle_params, Atom.to_string(rule)) == "true"

      if enabled? != Map.fetch!(current_flocking_rule_toggles, rule) do
        Boids.update_flocking_rule_toggles(rule, enabled?)
      end
    end

    {:noreply, socket}
  end

  def handle_event("spawn_boids", %{"spawn_boids" => %{"count" => count} = spawn_params}, socket) do
    socket = assign(socket, :spawn_boids_form, to_form(spawn_params, as: :spawn_boids))

    case Integer.parse(count) do
      {requested_count, ""} when requested_count > 0 ->
        spawned_count = Boids.spawn_boids_up_to_limit(requested_count)

        {:noreply,
         socket
         |> assign(:boid_count, Boids.boid_count())
         |> put_spawn_flash(requested_count, spawned_count)}

      _not_a_positive_whole_number ->
        {:noreply, put_flash(socket, :error, "Enter a whole number of boids to spawn.")}
    end
  end

  def handle_event("update_all_flocking_rule_toggles", %{"enabled" => enabled}, socket) do
    Boids.update_all_flocking_rule_toggles(enabled == "true")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:flocking_rule_toggles_updated, flocking_rule_toggles}, socket) do
    {:noreply, assign_flocking_rule_toggles_form(socket, flocking_rule_toggles)}
  end

  def handle_info(:render_frame, socket) do
    positions =
      Boids.list_boid_positions()
      |> Enum.map(fn {{_cell_x, _cell_y, _pid}, %Boid{position: {x, y}}} -> [x, y] end)

    Process.send_after(self(), :render_frame, @frame_interval_ms)

    # Boids can also be spawned from iex, so the count is refreshed every frame. assign/3
    # only marks it changed when the number differs, so a steady count re-renders nothing.
    {:noreply,
     socket
     |> assign(:boid_count, Boids.boid_count())
     |> push_event("update_boid_positions", %{positions: positions})}
  end

  defp put_spawn_flash(socket, requested_count, spawned_count)
       when spawned_count < requested_count do
    put_flash(
      socket,
      :info,
      "Spawned #{spawned_count} boids (the limit is #{Boids.max_boid_count()})."
    )
  end

  defp put_spawn_flash(socket, _requested_count, _spawned_count), do: socket

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
