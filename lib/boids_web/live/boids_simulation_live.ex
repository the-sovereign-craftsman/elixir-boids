defmodule BoidsWeb.BoidsSimulationLive do
  use BoidsWeb, :live_view

  alias Boids.Boid

  @frame_interval_ms div(1000, 24)

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
     |> assign_flocking_rule_toggles_form(Boids.flocking_rule_toggles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <%!-- Controls beside the canvas from md up; the telemetry column joins at xl. --%>
      <div class="grid items-start gap-6 md:grid-cols-[16rem_minmax(0,1fr)] xl:grid-cols-[16rem_minmax(0,1fr)_16rem]">
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

    {:noreply, push_event(socket, "update_boid_positions", %{positions: positions})}
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
