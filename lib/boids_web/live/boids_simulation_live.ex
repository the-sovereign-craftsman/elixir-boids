defmodule BoidsWeb.BoidsSimulationLive do
  use BoidsWeb, :live_view

  alias Boids.Boid

  @frame_interval_ms div(1000, 24)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :render_frame, @frame_interval_ms)
    end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <canvas
        id="boid-canvas"
        phx-hook=".BoidCanvas"
        phx-update="ignore"
        width="1000"
        height="1000"
        class="w-full max-w-2xl aspect-square border border-base-300"
      ></canvas>
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

  @impl true
  def handle_info(:render_frame, socket) do
    positions = Enum.map(Boids.list_boid_positions(), fn {_pid, %Boid{position: {x, y}}} -> [x, y] end)

    Process.send_after(self(), :render_frame, @frame_interval_ms)

    {:noreply, push_event(socket, "update_boid_positions", %{positions: positions})}
  end
end
