defmodule Boids.BoidFlockingSettingsTest do
  # Not async: there is one named settings process and table for the whole app,
  # and every test here changes it.
  use ExUnit.Case, async: false

  alias Boids.BoidFlockingSettings

  # Restart the application's settings process before each test, so every test
  # starts from the defaults that init/1 writes. Restarting also recreates the
  # table, since an ETS table is deleted when its owner process exits.
  setup do
    :ok = Supervisor.terminate_child(Boids.Supervisor, BoidFlockingSettings)
    {:ok, _pid} = Supervisor.restart_child(Boids.Supervisor, BoidFlockingSettings)
    :ok
  end

  describe "table" do
    test "is a named :set table" do
      assert :ets.info(BoidFlockingSettings.table_name(), :named_table) == true
      assert :ets.info(BoidFlockingSettings.table_name(), :type) == :set
    end

    test "is readable but not writable from a process other than its owner" do
      table_name = BoidFlockingSettings.table_name()

      assert [_row] = :ets.lookup(table_name, :enabled_flocking_rules)

      # The test process does not own the table, so this fails if it's :protected.
      assert_raise ArgumentError, fn ->
        :ets.insert(table_name, {:enabled_flocking_rules, %{}})
      end
    end

    test "starts with every flocking rule turned off" do
      assert enabled_flocking_rules() == %{separation: false, cohesion: false, alignment: false}
    end
  end

  describe "update_flocking_settings/2" do
    test "returns :ok" do
      assert BoidFlockingSettings.update_flocking_settings(:cohesion, true) == :ok
    end

    test "turns a rule on without changing the other rules" do
      BoidFlockingSettings.update_flocking_settings(:cohesion, true)

      assert enabled_flocking_rules() == %{separation: false, cohesion: true, alignment: false}
    end

    test "turns a rule back off" do
      BoidFlockingSettings.update_flocking_settings(:alignment, true)
      BoidFlockingSettings.update_flocking_settings(:alignment, false)

      assert enabled_flocking_rules() == %{separation: false, cohesion: false, alignment: false}
    end

    test "can turn every rule on" do
      BoidFlockingSettings.update_flocking_settings(:separation, true)
      BoidFlockingSettings.update_flocking_settings(:cohesion, true)
      BoidFlockingSettings.update_flocking_settings(:alignment, true)

      assert enabled_flocking_rules() == %{separation: true, cohesion: true, alignment: true}
    end

    test "turning on a rule that is already on leaves it on" do
      BoidFlockingSettings.update_flocking_settings(:separation, true)
      BoidFlockingSettings.update_flocking_settings(:separation, true)

      assert enabled_flocking_rules().separation == true
    end

    # These two call through apply/3 so the compiler doesn't flag the bad
    # arguments; the point is to check that the guard rejects them at runtime.
    test "rejects an unknown rule without changing the table" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingSettings, :update_flocking_settings, [:cohesoin, true])
      end

      assert enabled_flocking_rules() == %{separation: false, cohesion: false, alignment: false}
    end

    test "rejects a value that isn't a boolean" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(BoidFlockingSettings, :update_flocking_settings, [:cohesion, "true"])
      end

      assert enabled_flocking_rules().cohesion == false
    end
  end

  describe "restarting" do
    test "a restarted settings process starts over with every rule turned off" do
      BoidFlockingSettings.update_flocking_settings(:cohesion, true)

      :ok = Supervisor.terminate_child(Boids.Supervisor, BoidFlockingSettings)
      {:ok, _pid} = Supervisor.restart_child(Boids.Supervisor, BoidFlockingSettings)

      assert enabled_flocking_rules() == %{separation: false, cohesion: false, alignment: false}
    end
  end

  describe "Boids.update_flocking_settings/2" do
    test "changes the settings through Boids.BoidFlockingSettings" do
      assert Boids.update_flocking_settings(:separation, true) == :ok

      assert enabled_flocking_rules().separation == true
    end
  end

  # Reads the row straight from ETS. Swap for flocking_rule_states/0 once it exists.
  defp enabled_flocking_rules do
    [{:enabled_flocking_rules, enabled_flocking_rules}] =
      :ets.lookup(BoidFlockingSettings.table_name(), :enabled_flocking_rules)

    enabled_flocking_rules
  end
end
