defmodule Boids.BoidPositionsTest do
  use ExUnit.Case, async: true

  alias Boids.BoidPositions

  # The table is created once by the application's supervision tree, so these
  # tests inspect that running instance rather than starting a new one (a
  # second :named_table with the same name would fail to start).

  describe "table" do
    test "is a named :set table" do
      assert :ets.info(BoidPositions.table_name(), :named_table) == true
      assert :ets.info(BoidPositions.table_name(), :type) == :ordered_set
    end

    test "is writable from a process other than its owner" do
      key = make_ref()
      on_exit(fn -> :ets.delete(BoidPositions.table_name(), key) end)

      # The test process does not own the table, so this only works if it's :public.
      assert :ets.insert(BoidPositions.table_name(), {key, :row})
      assert :ets.lookup(BoidPositions.table_name(), key) == [{key, :row}]
    end
  end
end
