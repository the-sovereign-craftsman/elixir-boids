defmodule Boids.BoidServerTimerTest do
  # Not async: this test changes :tick_interval_ms in the application env, which is
  # global to the VM. Non-async modules run only after all async tests have finished,
  # so no other test can see the changed value.
  use ExUnit.Case, async: false

  import Mox

  alias Boids.Boid
  alias Boids.BoidMock
  alias Boids.BoidServer

  setup :verify_on_exit!

  # Every other BoidServer test runs with :tick_interval_ms set to :manual (config/test.exs)
  # and sends :tick itself. This is the one test of the production path: a real interval,
  # where the server schedules its own ticks.
  setup do
    original_interval = Application.fetch_env!(:boids, :tick_interval_ms)
    Application.put_env(:boids, :tick_interval_ms, 5)
    on_exit(fn -> Application.put_env(:boids, :tick_interval_ms, original_interval) end)
  end

  describe "with a real tick interval" do
    test "ticks on its own timer, and keeps rescheduling after each tick" do
      initial_boid = %Boid{position: {500.0, 500.0}, velocity: {0.0, 0.0}}
      test_pid = self()

      expect(BoidMock, :new, fn -> initial_boid end)

      # A stub rather than an expect: the timer keeps firing until the server is stopped,
      # so the number of calls isn't fixed.
      stub(BoidMock, :advance_boid, fn boid, _neighbors ->
        send(test_pid, :advanced_by_timer)
        boid
      end)

      start_supervised!({BoidServer, []})

      # The test never sends :tick. The first tick proves init/1 scheduled one; the
      # second proves handle_info/2 scheduled the next.
      assert_receive :advanced_by_timer
      assert_receive :advanced_by_timer
    end
  end
end
