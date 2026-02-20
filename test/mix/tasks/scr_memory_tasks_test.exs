defmodule Mix.Tasks.ScrMemoryTasksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("scr.memory.verify")
    Mix.Task.reenable("scr.memory.migrate")
    :ok
  end

  test "scr.memory.verify succeeds for ets backend" do
    output =
      capture_io(fn ->
        Mix.Tasks.Scr.Memory.Verify.run(["--backend", "ets"])
      end)

    assert output =~ "verify: ok"
  end

  test "scr.memory.migrate moves ets data to dets backend" do
    unique = System.unique_integer([:positive])
    dets_dir = Path.join(System.tmp_dir!(), "scr_memory_task_migrate_#{unique}")

    if :ets.whereis(:scr_tasks) == :undefined,
      do: :ets.new(:scr_tasks, [:set, :named_table, :public])

    if :ets.whereis(:scr_memory) == :undefined,
      do: :ets.new(:scr_memory, [:set, :named_table, :public])

    :ets.insert(:scr_tasks, {"task_mix_1", %{task_id: "task_mix_1"}})
    :ets.insert(:scr_memory, {"task_mix_1", %{task_id: "task_mix_1", result: "ok"}})

    _output =
      capture_io(fn ->
        Mix.Tasks.Scr.Memory.Migrate.run([
          "--from",
          "ets",
          "--to",
          "dets",
          "--to-path",
          dets_dir
        ])
      end)

    assert File.exists?(Path.join(dets_dir, "scr_tasks.dets"))
    assert File.exists?(Path.join(dets_dir, "scr_memory.dets"))
  end
end
