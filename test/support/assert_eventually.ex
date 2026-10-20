defmodule Boids.AssertEventually do
  @moduledoc """
  For tests that wait on something another process does asynchronously, like the
  janitor handling a `:DOWN` or a supervisor restarting a killed boid.
  """

  import ExUnit.Assertions

  @doc "Checks `condition` every 10 ms, failing if it is still false after about half a second."
  def assert_eventually(condition, attempts_left \\ 50) do
    cond do
      condition.() ->
        :ok

      attempts_left == 0 ->
        flunk("condition was never met")

      true ->
        Process.sleep(10)
        assert_eventually(condition, attempts_left - 1)
    end
  end
end
