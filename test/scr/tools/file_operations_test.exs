defmodule SCR.Tools.FileOperationsTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.FileOperations

  setup do
    original_tools = Application.get_env(:scr, :tools)

    tmp_root =
      Path.join(System.tmp_dir!(), "scr_file_ops_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_root)

    tools_cfg = Keyword.put(original_tools || [], :workspace_root, tmp_root)
    Application.put_env(:scr, :tools, tools_cfg)

    on_exit(fn ->
      Application.put_env(:scr, :tools, original_tools)
      File.rm_rf(tmp_root)
    end)

    %{tmp_root: tmp_root}
  end

  test "blocks path traversal outside workspace" do
    assert {:error, "Path is outside workspace root"} =
             FileOperations.execute(%{"operation" => "read", "path" => "../../etc/passwd"})
  end

  test "write and read work inside workspace", %{tmp_root: _tmp_root} do
    assert {:ok, %{path: "notes/result.txt"}} =
             FileOperations.execute(%{
               "operation" => "write",
               "path" => "notes/result.txt",
               "content" => "hello"
             })

    assert {:ok, %{content: "hello"}} =
             FileOperations.execute(%{"operation" => "read", "path" => "notes/result.txt"})
  end
end
