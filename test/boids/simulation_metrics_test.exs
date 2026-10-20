defmodule Boids.SimulationMetricsTest do
  use ExUnit.Case, async: true

  alias Boids.SimulationMetrics

  describe "build_snapshot/2" do
    test "tick rate is ticks per boid per second" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0, tick_count: 0, boid_process_count: 1000),
          sample(sampled_at_ms: 1000, tick_count: 30_000, boid_process_count: 1000)
        )

      assert snapshot.tick_rate_hz == 30.0
    end

    test "tick rate accounts for elapsed time" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0, tick_count: 0, boid_process_count: 1000),
          sample(sampled_at_ms: 2000, tick_count: 30_000, boid_process_count: 1000)
        )

      assert snapshot.tick_rate_hz == 15.0
    end

    test "tick rate is 0.0 when there are no boids" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0, tick_count: 0, boid_process_count: 0),
          sample(sampled_at_ms: 1000, tick_count: 0, boid_process_count: 0)
        )

      assert snapshot.tick_rate_hz == 0.0
    end

    test "counts the restarts since the previous sample" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0, restart_count: 0),
          sample(sampled_at_ms: 1000, restart_count: 5)
        )

      assert snapshot.restart_count == 5
      assert snapshot.restarts_since_previous_sample == 5
    end

    test "memory per boid is process memory divided by process count" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0),
          sample(sampled_at_ms: 1000, process_memory_bytes: 1_000_000, total_process_count: 500)
        )

      assert snapshot.memory_per_boid_bytes == 2000
    end

    test "scheduler utilization comes from the two scheduler samples" do
      snapshot =
        SimulationMetrics.build_snapshot(sample(sampled_at_ms: 0), sample(sampled_at_ms: 1000))

      assert snapshot.scheduler_utilization_percent >= 0.0
      assert snapshot.scheduler_utilization_percent <= 100.0

      assert length(snapshot.scheduler_utilization_percent_by_scheduler) ==
               :erlang.system_info(:schedulers)
    end

    test "overall CPU is the average of the per-scheduler figures, so it matches the bars" do
      snapshot =
        SimulationMetrics.build_snapshot(sample(sampled_at_ms: 0), sample(sampled_at_ms: 1000))

      by_scheduler = snapshot.scheduler_utilization_percent_by_scheduler

      assert_in_delta snapshot.scheduler_utilization_percent,
                      Enum.sum(by_scheduler) / length(by_scheduler),
                      0.0001
    end

    # Two samples can land in the same millisecond, like a sample sent by hand just as
    # the timer fires. There's no time to divide by, so the tick rate is reported as 0.0.
    # Restarts are a plain count, so they're still counted.
    test "tick rate is 0.0 when both samples were taken in the same millisecond" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 500, tick_count: 0, restart_count: 0, boid_process_count: 10),
          sample(sampled_at_ms: 500, tick_count: 30, restart_count: 2, boid_process_count: 10)
        )

      assert snapshot.tick_rate_hz == 0.0
      assert snapshot.restarts_since_previous_sample == 2
    end

    test "counts are taken from the current sample" do
      snapshot =
        SimulationMetrics.build_snapshot(
          sample(sampled_at_ms: 0),
          sample(
            sampled_at_ms: 1000,
            boid_process_count: 4812,
            total_process_count: 5231,
            total_memory_bytes: 182_000_000
          )
        )

      assert snapshot.boid_process_count == 4812
      assert snapshot.total_process_count == 5231
      assert snapshot.total_memory_bytes == 182_000_000
    end
  end

  describe "add_snapshot_to_history/2" do
    test "history adds the newest snapshot at the end" do
      assert SimulationMetrics.add_snapshot_to_history([:first], :second) == [:first, :second]
    end

    test "history keeps only the last 60 snapshots" do
      history = Enum.reduce(1..61, [], &SimulationMetrics.add_snapshot_to_history(&2, &1))

      assert length(history) == 60
      assert List.first(history) == 2
      assert List.last(history) == 61
    end
  end

  # A raw sample with harmless defaults. Each test overrides only the fields it checks.
  defp sample(overrides) do
    defaults = %{
      sampled_at_ms: 0,
      tick_count: 0,
      scheduler_sample: :scheduler.sample(),
      boid_process_count: 0,
      total_process_count: 1,
      total_memory_bytes: 0,
      process_memory_bytes: 0,
      restart_count: 0
    }

    Map.merge(defaults, Map.new(overrides))
  end
end

defmodule Boids.SimulationMetricsProcessTest do
  # Not async: these tests restart the app-wide metrics process and change
  # :tick_interval_ms, which every test shares.
  use ExUnit.Case, async: false

  alias Boids.SimulationMetrics

  describe "the metrics process" do
    test "broadcasts a snapshot and history when it collects a sample" do
      SimulationMetrics.subscribe_to_simulation_metrics()

      # Triggers a sample now instead of waiting for the one-second timer.
      send(SimulationMetrics, :collect_sample)

      assert_receive {:simulation_metrics_updated, %{tick_rate_hz: _tick_rate_hz},
                      [_newest_snapshot | _older_snapshots]}
    end

    test "record_tick adds one to the tick count" do
      tick_count_before = SimulationMetrics.tick_count()

      SimulationMetrics.record_tick()

      assert SimulationMetrics.tick_count() == tick_count_before + 1
    end

    test "a restarted metrics process gets a fresh counter that record_tick still finds" do
      :ok = Supervisor.terminate_child(Boids.Supervisor, SimulationMetrics)
      {:ok, _pid} = Supervisor.restart_child(Boids.Supervisor, SimulationMetrics)

      SimulationMetrics.record_tick()

      assert SimulationMetrics.tick_count() == 1
    end
  end

  describe "target_tick_rate_hz/0" do
    setup do
      original_interval = Application.fetch_env!(:boids, :tick_interval_ms)
      on_exit(fn -> Application.put_env(:boids, :tick_interval_ms, original_interval) end)
    end

    test "is nil when ticks are sent by hand, as in tests" do
      Application.put_env(:boids, :tick_interval_ms, :manual)

      assert SimulationMetrics.target_tick_rate_hz() == nil
    end

    test "is how many ticks per second the interval allows" do
      Application.put_env(:boids, :tick_interval_ms, 50)

      assert SimulationMetrics.target_tick_rate_hz() == 20.0
    end

    test "is reachable through the Boids context" do
      Application.put_env(:boids, :tick_interval_ms, 50)

      assert Boids.target_tick_rate_hz() == 20.0
    end
  end
end
