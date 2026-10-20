defmodule BoidsWeb.SimulationDashboardComponents do
  @moduledoc """
  The telemetry dashboard beside the canvas. It renders the snapshots that
  `Boids.SimulationMetrics` broadcasts every second: a number for the latest
  value of each metric, and a sparkline of the last minute under it.

  Everything is server-rendered HEEx and inline SVG, with no JS or chart library.
  """

  use BoidsWeb, :html

  # Matches the history SimulationMetrics keeps, so a full minute fills the sparkline.
  @sparkline_capacity 60
  @sparkline_width 100
  @sparkline_height 24

  attr :snapshot, :map, default: nil, doc: "the newest snapshot, or nil before the first one"
  attr :history, :list, default: [], doc: "the last minute of snapshots, oldest first"
  attr :target_tick_rate_hz, :float, default: nil

  def simulation_dashboard(%{snapshot: nil} = assigns) do
    ~H"""
    <section id="simulation-dashboard" class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title">BEAM</h2>
        <p class="text-sm text-base-content/70">Waiting for metrics…</p>
      </div>
    </section>
    """
  end

  def simulation_dashboard(assigns) do
    ~H"""
    <section id="simulation-dashboard" class="card bg-base-200">
      <div class="card-body gap-4">
        <h2 class="card-title">BEAM</h2>

        <div>
          <.metric_row id="boid-process-count" label="Boid processes">
            {format_integer_with_commas(@snapshot.boid_process_count)}
          </.metric_row>
          <.sparkline
            id="boid-process-count-sparkline"
            values={metric_history(@history, :boid_process_count)}
          />
          <.metric_row id="total-process-count" label="Total processes">
            {format_integer_with_commas(@snapshot.total_process_count)}
          </.metric_row>
        </div>

        <div>
          <.metric_row id="tick-rate" label="Tick rate">
            {tick_rate_text(@snapshot.tick_rate_hz, @target_tick_rate_hz)}
          </.metric_row>
          <.sparkline id="tick-rate-sparkline" values={metric_history(@history, :tick_rate_hz)} />
        </div>

        <div>
          <%!-- Restarts finish within milliseconds, so a per-second figure is back to 0 a
               second after a kill. The headline adds up the minute of history instead, so a
               kill stays on screen until it scrolls out of the sparkline. The total only
               ever grows. --%>
          <.metric_row id="restarts-last-minute" label="Restarts (last min)">
            {format_integer_with_commas(restarts_in_history(@history))}
          </.metric_row>
          <.sparkline
            id="restarts-sparkline"
            values={metric_history(@history, :restarts_since_previous_sample)}
          />
          <.metric_row id="restart-count" label="Total restarts">
            {format_integer_with_commas(@snapshot.restart_count)}
          </.metric_row>
        </div>

        <div>
          <.metric_row
            id="scheduler-utilization"
            label={"CPU (#{length(@snapshot.scheduler_utilization_percent_by_scheduler)} schedulers)"}
          >
            {round(@snapshot.scheduler_utilization_percent)}%
          </.metric_row>
          <%!-- One bar per scheduler; the BEAM runs one scheduler per CPU core. --%>
          <%!-- Each bar is a full-height track with the busy share filled from the bottom,
               so idle schedulers still show as empty slots. --%>
          <div id="scheduler-bars" class="mt-2 flex h-10 gap-0.5">
            <div
              :for={scheduler_percent <- @snapshot.scheduler_utilization_percent_by_scheduler}
              class="flex flex-1 items-end overflow-hidden rounded-sm bg-base-300"
              title={"#{round(scheduler_percent)}%"}
            >
              <div class="w-full bg-primary" style={"height: #{scheduler_percent}%"}></div>
            </div>
          </div>
        </div>

        <div>
          <.metric_row id="memory-usage" label="Memory">
            {format_bytes(@snapshot.total_memory_bytes)}
          </.metric_row>
          <.sparkline id="memory-sparkline" values={metric_history(@history, :total_memory_bytes)} />
          <%!-- Per process rather than per boid: process memory averaged over every
               process, which boids dominate but don't make up alone. --%>
          <.metric_row id="memory-per-process" label="Per process">
            {format_bytes(@snapshot.memory_per_boid_bytes)}
          </.metric_row>
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp metric_row(assigns) do
    ~H"""
    <div class="flex items-baseline justify-between gap-2 text-sm">
      <span class="text-base-content/70">{@label}</span>
      <span id={@id} class="whitespace-nowrap font-mono tabular-nums">
        {render_slot(@inner_block)}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :values, :list, required: true, doc: "numbers, oldest first"

  @doc """
  A small line chart of `values`. The newest value sits at the right edge, so the
  line grows in from the right until a full minute of history fills it. The
  vertical scale runs from 0 to the largest value, so a steady metric reads as flat.
  """
  def sparkline(assigns) do
    points = sparkline_points(assigns.values)

    assigns =
      assign(assigns,
        line_points: format_svg_points(points),
        area_points: format_svg_points(close_area_under_line(points)),
        width: @sparkline_width,
        height: @sparkline_height
      )

    ~H"""
    <svg
      id={@id}
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      class="mt-1 h-8 w-full text-primary"
      aria-hidden="true"
    >
      <polygon points={@area_points} fill="currentColor" fill-opacity="0.15" />
      <polyline
        points={@line_points}
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  # One {x, y} per value. Each value takes one of @sparkline_capacity slots, counted
  # back from the right edge.
  defp sparkline_points(values) do
    # The top of the chart is 25% above the largest value, so a steady metric reads as a
    # line in the upper part of the chart rather than a rule along its top edge. At least
    # 1, so all-zero values don't divide by zero; they draw along the bottom.
    chart_top_value = max(Enum.max(values, fn -> 0 end) * 1.25, 1)
    first_slot = @sparkline_capacity - length(values)
    slot_width = @sparkline_width / (@sparkline_capacity - 1)

    values
    |> Enum.with_index(first_slot)
    |> Enum.map(fn {value, slot} ->
      # SVG y runs downward, so a larger value means a smaller y. One unit of padding
      # at the bottom keeps the stroke from being clipped.
      {slot * slot_width,
       @sparkline_height - 1 - value / chart_top_value * (@sparkline_height - 1)}
    end)
  end

  # The shaded area under the line: the line's points, then down to the bottom edge
  # and back along it to where the line started.
  defp close_area_under_line([]), do: []

  defp close_area_under_line(points) do
    {first_x, _first_y} = List.first(points)
    {last_x, _last_y} = List.last(points)
    points ++ [{last_x, @sparkline_height}, {first_x, @sparkline_height}]
  end

  # "x1,y1 x2,y2 ...", the format <polyline> and <polygon> take.
  defp format_svg_points(points) do
    Enum.map_join(points, " ", fn {x, y} ->
      "#{Float.round(x / 1, 2)},#{Float.round(y / 1, 2)}"
    end)
  end

  defp metric_history(history, metric), do: Enum.map(history, &Map.fetch!(&1, metric))

  # Every restart in the history window: up to the last minute, one sample per second.
  defp restarts_in_history(history) do
    history
    |> metric_history(:restarts_since_previous_sample)
    |> Enum.sum()
  end

  # "29.0 / 30.3 Hz", or "29.0 Hz" when there is no target (ticks sent by hand in tests).
  defp tick_rate_text(tick_rate_hz, nil), do: "#{format_decimal(tick_rate_hz)} Hz"

  defp tick_rate_text(tick_rate_hz, target_tick_rate_hz) do
    "#{format_decimal(tick_rate_hz)} / #{format_decimal(target_tick_rate_hz)} Hz"
  end

  defp format_decimal(number), do: :erlang.float_to_binary(number / 1, decimals: 1)

  defp format_bytes(bytes) when bytes >= 1_000_000, do: "#{round(bytes / 1_000_000)} MB"
  defp format_bytes(bytes), do: "#{format_decimal(bytes / 1000)} KB"

  # 4812 -> "4,812". Groups the digits in threes from the right.
  defp format_integer_with_commas(integer) do
    integer
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
