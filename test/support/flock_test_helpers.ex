defmodule Boids.FlockTestHelpers do
  @moduledoc """
  For tests that kill real boids and wait for their supervisor to restart them.
  """

  import Boids.AssertEventually

  @doc "The pids of the boids that are running right now, skipping any mid-restart."
  def running_boid_pids do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Boids.DynamicSupervisor),
        is_pid(pid),
        do: pid
  end

  @doc """
  Waits until `killed_count` of the boids in `pids_before_kill` are gone and the
  supervisor has replaced every one of them.

  Checking only the boid count isn't enough. `Boids.kill_boids/1` returns as soon as
  the kill signals are sent, so straight after it the count is unchanged because the
  boids haven't died yet. A test that finished then would leave restarts in flight
  after its Mox stub had ended, and they'd leak into the next test.
  """
  def assert_killed_boids_replaced(pids_before_kill, killed_count) do
    assert_eventually(fn ->
      running_pids = running_boid_pids()
      surviving_count = Enum.count(running_pids, &(&1 in pids_before_kill))

      surviving_count == length(pids_before_kill) - killed_count and
        length(running_pids) == length(pids_before_kill)
    end)
  end
end
