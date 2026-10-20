defmodule Boids.CpuHogsTest do
  # Not async: hogs run under the app's one CpuHogSupervisor, and they really do use a
  # whole CPU core each, so every test stops them all when it's done.
  use ExUnit.Case, async: false

  import Boids.AssertEventually

  setup do
    on_exit(&Boids.stop_cpu_hogs/0)
    :ok
  end

  test "start_cpu_hog starts a running hog" do
    pid = Boids.start_cpu_hog()

    assert Process.alive?(pid)
    assert Boids.cpu_hog_count() == 1
  end

  test "start_cpu_hogs starts that many hogs" do
    pids = Boids.start_cpu_hogs(3)

    assert length(pids) == 3
    assert Boids.cpu_hog_count() == 3
  end

  test "stop_cpu_hogs stops every hog" do
    pids = Boids.start_cpu_hogs(2)

    assert Boids.stop_cpu_hogs() == :ok

    assert Boids.cpu_hog_count() == 0
    refute Enum.any?(pids, &Process.alive?/1)
  end

  test "a hog that dies is not restarted" do
    pid = Boids.start_cpu_hog()

    Process.exit(pid, :kill)

    assert_eventually(fn -> Boids.cpu_hog_count() == 0 end)
  end

  test "hogs are not boids" do
    boid_count_before = Boids.boid_count()

    Boids.start_cpu_hog()

    assert Boids.boid_count() == boid_count_before
  end

  # The point of the demo: with a hog spinning on every scheduler, the BEAM still
  # preempts them and gives other processes their turn.
  test "other processes still run while every scheduler has a hog" do
    Boids.start_cpu_hogs(:erlang.system_info(:schedulers_online))

    task = Task.async(fn -> :still_scheduled end)

    assert Task.await(task, 1000) == :still_scheduled
  end
end
