defmodule Boids.FlockTestHelpers do
  @moduledoc """
  For tests that kill real boids and wait for their supervisor to restart them.
  """

  import Boids.AssertEventually

  @doc """
  Spawns `count` boids and waits until the janitor is watching all of them.

  Each boid registers with the janitor by a cast while it starts. A boid killed before
  the janitor has handled that cast dies unwatched (the janitor's :noproc case), and its
  death isn't counted. Tests that kill boids and check the crash count spawn them here.
  """
  def spawn_watched_boids(count) do
    pids = Boids.spawn_boids(count)
    # spawn_boids/1 returns once every boid's init/1 has run, so every registration has
    # been sent. This call is handled after them, so once it returns they're all watched.
    :sys.get_state(Boids.BoidJanitor)
    pids
  end

  @doc "The pids of the boids that are running right now, skipping any mid-restart."
  def running_boid_pids, do: Boids.boid_pids()

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
