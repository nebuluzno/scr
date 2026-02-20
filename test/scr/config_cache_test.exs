defmodule SCR.ConfigCacheTest do
  use ExUnit.Case, async: false

  test "refresh and get return updated values" do
    original = Application.get_env(:scr, :task_queue, [])

    on_exit(fn ->
      Application.put_env(:scr, :task_queue, original)
      SCR.ConfigCache.refresh(:task_queue)
    end)

    Application.put_env(:scr, :task_queue, Keyword.merge(original, max_size: 321))
    _ = SCR.ConfigCache.refresh(:task_queue)

    cfg = SCR.ConfigCache.get(:task_queue, [])
    assert Keyword.get(cfg, :max_size) == 321
  end
end
