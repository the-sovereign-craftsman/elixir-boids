defmodule Boids.BoidFlockingRuleTogglesTest do
  # Not async: there is one named toggles process and table for the whole app,
  # and every test here changes it.
  use ExUnit.Case, async: false

  alias Boids.BoidFlockingRuleToggles

  # Restart the application's toggles process before each test, so every test
  # starts from the defaults that init/1 writes. Restarting also recreates the
  # table, since an ETS table is deleted when its owner process exits.
  setup do
    :ok = Supervisor.terminate_child(Boids.Supervisor, BoidFlockingRuleToggles)
    {:ok, _pid} = Supervisor.restart_child(Boids.Supervisor, BoidFlockingRuleToggles)
    :ok
  end

  describe "table" do
    test "is a named :set table" do
      assert :ets.info(BoidFlockingRuleToggles.table_name(), :named_table) == true
      assert :ets.info(BoidFlockingRuleToggles.table_name(), :type) == :set
    end

    test "is readable but not writable from a process other than its owner" do
      table_name = BoidFlockingRuleToggles.table_name()

      assert [_row] = :ets.lookup(table_name, :enabled_flocking_rules)

      # The test process does not own the table, so this fails if it's :protected.
      assert_raise ArgumentError, fn ->
        :ets.insert(table_name, {:enabled_flocking_rules, %{}})
      end
    end

    test "starts with every flocking rule turned off" do
      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: false,
               cohesion: false,
               alignment: false
             }
    end
  end

  describe "update_flocking_rule_toggles/2" do
    test "returns :ok" do
      assert BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true) == :ok
    end

    test "turns a rule on without changing the other rules" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: false,
               cohesion: true,
               alignment: false
             }
    end

    test "turns a rule back off" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, false)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: false,
               cohesion: false,
               alignment: false
             }
    end

    test "can turn every rule on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true)
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: true,
               cohesion: true,
               alignment: true
             }
    end

    test "turning on a rule that is already on leaves it on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles().separation == true
    end

    # These two call through apply/3 so the compiler doesn't flag the bad
    # arguments; the point is to check that the guard rejects them at runtime.
    test "rejects an unknown rule without changing the table" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingRuleToggles, :update_flocking_rule_toggles, [:cohesoin, true])
      end

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: false,
               cohesion: false,
               alignment: false
             }
    end

    test "rejects a value that isn't a boolean" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingRuleToggles, :update_flocking_rule_toggles, [:cohesion, "true"])
      end

      assert BoidFlockingRuleToggles.flocking_rule_toggles().cohesion == false
    end
  end

  describe "flocking_rule_toggles/0" do
    test "returns the map stored in the table" do
      [{:enabled_flocking_rules, stored_toggles}] =
        :ets.lookup(BoidFlockingRuleToggles.table_name(), :enabled_flocking_rules)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == stored_toggles
    end

    test "sees a change as soon as update_flocking_rule_toggles/2 returns" do
      :ok = BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles().alignment == true
    end

    test "can be read from a process other than the table's owner" do
      test_pid = self()

      spawn(fn ->
        send(test_pid, {:toggles_read, BoidFlockingRuleToggles.flocking_rule_toggles()})
      end)

      assert_receive {:toggles_read, %{separation: false, cohesion: false, alignment: false}}
    end
  end

  describe "restarting" do
    test "a restarted toggles process starts over with every rule turned off" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true)

      :ok = Supervisor.terminate_child(Boids.Supervisor, BoidFlockingRuleToggles)
      {:ok, _pid} = Supervisor.restart_child(Boids.Supervisor, BoidFlockingRuleToggles)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: false,
               cohesion: false,
               alignment: false
             }
    end
  end

  describe "Boids.update_flocking_rule_toggles/2" do
    test "changes the toggles through Boids.BoidFlockingRuleToggles" do
      assert Boids.update_flocking_rule_toggles(:separation, true) == :ok

      assert BoidFlockingRuleToggles.flocking_rule_toggles().separation == true
    end
  end
end
