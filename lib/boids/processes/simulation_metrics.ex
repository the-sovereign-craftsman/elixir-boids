defmodule Boids.SimulationMetrics do
  @moduledoc """
  Measures the running simulation for the dashboard.

  A raw `t:sample/0` is a reading of the VM at one moment. A `t:snapshot/0` is
  what happened between two samples, like how many ticks each boid made per
  second. The math lives in pure functions (`build_snapshot/2`,
  `add_snapshot_to_history/2`), so it can be tested with made-up samples.

  The process takes a sample every second, builds a snapshot from it and the
  previous sample, and broadcasts the snapshot with the last minute of history
  as `{:simulation_metrics_updated, snapshot, history}`.

  Ticks are counted with a `:counters` ref rather than messages, so thousands of
  boids can count every tick without queueing behind this process. The ref is
  stored in `:persistent_term` once at startup, where every boid can read it
  without copying.
  """

  use GenServer

  alias Boids.BoidJanitor

  # How many snapshots the dashboard's sparklines show: one minute at one per second.
  @history_length 60
  @sample_interval_ms 1000
  @pubsub_topic "simulation_metrics"
  @tick_counter_key {__MODULE__, :tick_counter}

  @type sample :: %{
          sampled_at_ms: integer(),
          tick_count: non_neg_integer(),
          scheduler_sample: term(),
          boid_process_count: non_neg_integer(),
          total_process_count: non_neg_integer(),
          total_memory_bytes: non_neg_integer(),
          process_memory_bytes: non_neg_integer(),
          restart_count: non_neg_integer()
        }

  @type snapshot :: %{
          boid_process_count: non_neg_integer(),
          total_process_count: non_neg_integer(),
          tick_rate_hz: float(),
          restart_count: non_neg_integer(),
          restarts_since_previous_sample: non_neg_integer(),
          scheduler_utilization_percent: float(),
          scheduler_utilization_percent_by_scheduler: [float()],
          total_memory_bytes: non_neg_integer(),
          memory_per_boid_bytes: non_neg_integer()
        }

  @type state :: %{previous_sample: sample(), history: [snapshot()]}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Counts one boid tick. Called by every boid on every tick."
  @spec record_tick() :: :ok
  def record_tick do
    @tick_counter_key
    |> :persistent_term.get()
    |> :counters.add(1, 1)
  end

  @doc "Every tick counted since the metrics process started."
  @spec tick_count() :: non_neg_integer()
  def tick_count do
    @tick_counter_key
    |> :persistent_term.get()
    |> :counters.get(1)
  end

  @doc """
  How many times per second each boid should tick, from `:tick_interval_ms`.
  `nil` when ticks are sent by hand (`:manual`, in tests).
  """
  @spec target_tick_rate_hz() :: float() | nil
  def target_tick_rate_hz do
    case Application.fetch_env!(:boids, :tick_interval_ms) do
      :manual -> nil
      tick_interval_ms -> 1000 / tick_interval_ms
    end
  end

  def subscribe_to_simulation_metrics, do: Phoenix.PubSub.subscribe(Boids.PubSub, @pubsub_topic)

  @impl true
  def init(:ok) do
    # A restart replaces the counter, so the tick count starts again from 0. The
    # first snapshot after a restart compares against a fresh sample, so it stays correct.
    :persistent_term.put(@tick_counter_key, :counters.new(1, [:write_concurrency]))

    schedule_sample()
    {:ok, %{previous_sample: take_sample(), history: []}}
  end

  @impl true
  def handle_info(:collect_sample, %{previous_sample: previous_sample, history: history}) do
    current_sample = take_sample()
    snapshot = build_snapshot(previous_sample, current_sample)
    updated_history = add_snapshot_to_history(history, snapshot)

    Phoenix.PubSub.broadcast(
      Boids.PubSub,
      @pubsub_topic,
      {:simulation_metrics_updated, snapshot, updated_history}
    )

    schedule_sample()
    {:noreply, %{previous_sample: current_sample, history: updated_history}}
  end

  @doc """
  Turns two samples into a snapshot of what happened between them. Counts and
  memory come from the current sample; rates are deltas over the elapsed time.
  """
  @spec build_snapshot(sample(), sample()) :: snapshot()
  def build_snapshot(previous_sample, current_sample) do
    elapsed_seconds = (current_sample.sampled_at_ms - previous_sample.sampled_at_ms) / 1000

    ticks_per_second =
      per_second(current_sample.tick_count - previous_sample.tick_count, elapsed_seconds)

    {scheduler_utilization_percent, scheduler_utilization_percent_by_scheduler} =
      scheduler_utilization_percents(
        previous_sample.scheduler_sample,
        current_sample.scheduler_sample
      )

    %{
      boid_process_count: current_sample.boid_process_count,
      total_process_count: current_sample.total_process_count,
      tick_rate_hz: tick_rate_per_boid(ticks_per_second, current_sample.boid_process_count),
      restart_count: current_sample.restart_count,
      # A plain count rather than a rate: a mass kill restarts every boid within
      # milliseconds, so it all lands in one sample either way.
      restarts_since_previous_sample:
        current_sample.restart_count - previous_sample.restart_count,
      scheduler_utilization_percent: scheduler_utilization_percent,
      scheduler_utilization_percent_by_scheduler: scheduler_utilization_percent_by_scheduler,
      total_memory_bytes: current_sample.total_memory_bytes,
      memory_per_boid_bytes:
        div(current_sample.process_memory_bytes, current_sample.total_process_count)
    }
  end

  @doc "Adds a snapshot as the newest entry, keeping only the last #{@history_length}."
  @spec add_snapshot_to_history([snapshot()], snapshot()) :: [snapshot()]
  def add_snapshot_to_history(history, snapshot) do
    Enum.take(history ++ [snapshot], -@history_length)
  end

  defp schedule_sample, do: Process.send_after(self(), :collect_sample, @sample_interval_ms)

  defp take_sample do
    %{
      sampled_at_ms: System.monotonic_time(:millisecond),
      tick_count: tick_count(),
      scheduler_sample: :scheduler.sample(),
      boid_process_count: Boids.boid_count(),
      total_process_count: :erlang.system_info(:process_count),
      total_memory_bytes: :erlang.memory(:total),
      process_memory_bytes: :erlang.memory(:processes),
      # Every crash of a boid leads to one restart by its supervisor.
      restart_count: BoidJanitor.crash_count()
    }
  end

  # Ticks are counted across all boids, so dividing by the boid count gives
  # how often each boid ticked. With no boids nothing ticked.
  # Two samples in the same millisecond, like one sent by hand just as the timer fires,
  # leave no time to divide by. 0.0 rather than a crash.
  defp per_second(_change, elapsed_seconds) when elapsed_seconds == 0, do: 0.0
  defp per_second(change, elapsed_seconds), do: change / elapsed_seconds

  defp tick_rate_per_boid(_ticks_per_second, 0), do: 0.0
  defp tick_rate_per_boid(ticks_per_second, boid_count), do: ticks_per_second / boid_count

  # :scheduler.utilization/2 returns one tuple per measurement. Each :normal entry is
  # one normal scheduler (one per CPU core), which is where the boids run. The overall
  # figure is their average, so it always agrees with the per-scheduler bars. (Its own
  # :weighted figure also counts the dirty CPU schedulers, which run long native code
  # rather than boids, and can read above 100%.)
  defp scheduler_utilization_percents(previous_scheduler_sample, current_scheduler_sample) do
    utilization = :scheduler.utilization(previous_scheduler_sample, current_scheduler_sample)

    utilization_percent_by_scheduler =
      for {:normal, _scheduler_id, scheduler_utilization, _percent_text} <- utilization,
          do: scheduler_utilization * 100

    average_utilization_percent =
      Enum.sum(utilization_percent_by_scheduler) / length(utilization_percent_by_scheduler)

    {average_utilization_percent, utilization_percent_by_scheduler}
  end
end
