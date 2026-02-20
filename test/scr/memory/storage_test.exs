defmodule SCR.Memory.StorageTest do
  use ExUnit.Case, async: false

  alias SCR.Memory.Storage

  test "verify_data reports orphan result warnings" do
    data = %{
      scr_tasks: %{"t1" => %{task_id: "t1"}},
      scr_memory: %{"t1" => %{ok: true}, "t2" => %{ok: false}},
      scr_agent_states: %{}
    }

    report = Storage.verify_data(data)
    assert report.errors == []
    assert report.counts.scr_tasks == 1
    assert report.counts.scr_memory == 2
    assert length(report.warnings) == 1
  end

  test "migrates data from dets to sqlite and preserves counts" do
    if is_nil(System.find_executable("sqlite3")) do
      :ok
    else
      unique = System.unique_integer([:positive])
      dets_dir = Path.join(System.tmp_dir!(), "scr_storage_dets_#{unique}")
      sqlite_path = Path.join(System.tmp_dir!(), "scr_storage_sqlite_#{unique}.sqlite3")

      data = %{
        scr_tasks: %{"task_1" => %{task_id: "task_1", description: "migrate"}},
        scr_memory: %{"task_1" => %{task_id: "task_1", result: "ok"}},
        scr_agent_states: %{"worker_1" => %{agent_id: "worker_1", status: "idle"}}
      }

      assert :ok = Storage.clear_backend(:dets, path: dets_dir)
      assert :ok = Storage.write_backend(:dets, data, path: dets_dir)
      assert :ok = Storage.clear_backend(:sqlite, path: sqlite_path)

      assert {:ok, dets_data} = Storage.read_backend(:dets, path: dets_dir)
      assert :ok = Storage.write_backend(:sqlite, dets_data, path: sqlite_path)
      assert {:ok, sqlite_data} = Storage.read_backend(:sqlite, path: sqlite_path)

      assert map_size(sqlite_data.scr_tasks) == 1
      assert map_size(sqlite_data.scr_memory) == 1
      assert map_size(sqlite_data.scr_agent_states) == 1
      assert sqlite_data.scr_tasks["task_1"].description == "migrate"
    end
  end
end
