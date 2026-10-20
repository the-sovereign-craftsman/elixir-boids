defmodule Boids.CpuHog do
  @moduledoc """
  A runaway process for the fair-scheduling demo. It loops forever doing pointless
  arithmetic, never waiting, never receiving a message, never giving up the CPU.

  In most runtimes a thread like this could starve everything else on its core. The
  BEAM preempts every process after a fixed budget of work (its "reductions"), however
  busy it is, so the boids still get their turns. With one hog, one scheduler pins at
  100% and the flock carries on. With a hog on every scheduler, the boids share the
  CPU with the hogs, so the tick rate drops, but they never stop.

  Hogs run under `Boids.CpuHogSupervisor`, apart from the boids, and are never
  restarted: stopping one is always intentional.
  """

  use Task, restart: :temporary

  def start_link(_opts), do: Task.start_link(fn -> spin(0) end)

  # The number is meaningless; the loop only exists to keep the CPU busy. The rem keeps
  # it small, so the loop never slows into big-integer arithmetic.
  defp spin(number), do: spin(rem(number * 7 + 3, 1_000_003))
end
