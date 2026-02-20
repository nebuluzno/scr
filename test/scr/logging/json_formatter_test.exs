defmodule SCR.Logging.JSONFormatterTest do
  use ExUnit.Case, async: true

  test "formats log event as JSON line" do
    iodata =
      SCR.Logging.JSONFormatter.format(
        :info,
        {"hello ~s", ["world"]},
        {{2026, 2, 20}, {12, 0, 0, 0}},
        trace_id: "trace_1",
        task_id: "task_1"
      )

    output = IO.iodata_to_binary(iodata)
    assert String.ends_with?(output, "\n")
    assert {:ok, payload} = Jason.decode(String.trim_trailing(output, "\n"))
    assert payload["level"] == "info"
    assert payload["message"] == "hello world"
    assert payload["metadata"]["trace_id"] == "trace_1"
    assert payload["metadata"]["task_id"] == "task_1"
  end
end
