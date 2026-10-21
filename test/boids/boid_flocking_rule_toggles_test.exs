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
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() == %{
               separation: true,
               cohesion: false,
               alignment: false
             }
    end

    test "turns a rule back off" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, false)

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

  describe "update_all_flocking_rule_toggles/1" do
    test "returns :ok" do
      assert BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true) == :ok
    end

    test "turns every rule on" do
      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: true}
    end

    test "turns every rule off" do
      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true)
      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(false)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: false, cohesion: false, alignment: false}
    end

    test "overrides a mix of rules that were on and off" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: true}
    end

    test "rejects a value that isn't a boolean without changing the table" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingRuleToggles, :update_all_flocking_rule_toggles, ["true"])
      end

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: false, cohesion: false, alignment: false}
    end
  end

  # Separation is the only rule that pushes boids apart. Without it, cohesion pulls the
  # flock together and alignment lets groups merge and never split, so the flock packs
  # tighter and tighter, every boid's neighbor list grows, and memory runs out. So the
  # toggles never hold cohesion or alignment without separation: the change that would
  # create that combination brings the other rules along.
  describe "keeping the flock from collapsing" do
    test "turning cohesion on also turns separation on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: false}
    end

    test "turning alignment on also turns separation on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: false, alignment: true}
    end

    test "turning separation off also turns cohesion and alignment off" do
      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true)

      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, false)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: false, cohesion: false, alignment: false}
    end

    test "turning cohesion off leaves separation on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, true)

      BoidFlockingRuleToggles.update_flocking_rule_toggles(:cohesion, false)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: false, alignment: false}
    end

    test "turning alignment off leaves separation on" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)

      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, false)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: false, alignment: false}
    end

    test "turning separation on leaves cohesion and alignment off" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: false, alignment: false}
    end

    test "subscribers get the adjusted state, in a single update" do
      :ok = BoidFlockingRuleToggles.subscribe_to_flocking_rule_toggles()

      BoidFlockingRuleToggles.update_flocking_rule_toggles(:alignment, true)

      assert_receive {:flocking_rule_toggles_updated,
                      %{separation: true, cohesion: false, alignment: true}}

      refute_receive {:flocking_rule_toggles_updated, _another_update}
    end

    test "never holds cohesion or alignment without separation, whatever the order of changes" do
      for _change <- 1..300 do
        rule = Enum.random([:separation, :cohesion, :alignment])
        BoidFlockingRuleToggles.update_flocking_rule_toggles(rule, Enum.random([true, false]))

        toggles = BoidFlockingRuleToggles.flocking_rule_toggles()

        refute (toggles.cohesion or toggles.alignment) and not toggles.separation,
               "unsafe toggles: #{inspect(toggles)}"
      end
    end
  end

  describe "subscribe_to_flocking_rule_toggles/0" do
    test "subscribers get the new state of every rule after a change" do
      :ok = BoidFlockingRuleToggles.subscribe_to_flocking_rule_toggles()

      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      assert_receive {:flocking_rule_toggles_updated,
                      %{separation: true, cohesion: false, alignment: false}}
    end

    test "turning every rule on sends a single update, with every rule on" do
      :ok = BoidFlockingRuleToggles.subscribe_to_flocking_rule_toggles()

      BoidFlockingRuleToggles.update_all_flocking_rule_toggles(true)

      assert_receive {:flocking_rule_toggles_updated,
                      %{separation: true, cohesion: true, alignment: true}}

      refute_receive {:flocking_rule_toggles_updated, _another_update}
    end

    test "a rejected change sends nothing" do
      :ok = BoidFlockingRuleToggles.subscribe_to_flocking_rule_toggles()

      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingRuleToggles, :update_flocking_rule_toggles, [:cohesoin, true])
      end

      refute_receive {:flocking_rule_toggles_updated, _flocking_rule_toggles}
    end
  end

  describe "Boids.flocking_rule_toggles/0" do
    test "returns the toggles from Boids.BoidFlockingRuleToggles" do
      BoidFlockingRuleToggles.update_flocking_rule_toggles(:separation, true)

      assert Boids.flocking_rule_toggles() == BoidFlockingRuleToggles.flocking_rule_toggles()
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

  describe "Boids.update_all_flocking_rule_toggles/1" do
    test "changes every toggle through Boids.BoidFlockingRuleToggles" do
      assert Boids.update_all_flocking_rule_toggles(true) == :ok

      assert BoidFlockingRuleToggles.flocking_rule_toggles() ==
               %{separation: true, cohesion: true, alignment: true}
    end
  end

  describe "Boids.update_flocking_rule_toggles/2" do
    test "changes the toggles through Boids.BoidFlockingRuleToggles" do
      assert Boids.update_flocking_rule_toggles(:separation, true) == :ok

      assert BoidFlockingRuleToggles.flocking_rule_toggles().separation == true
    end
  end
end
