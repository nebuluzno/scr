defmodule SCR do
  @moduledoc """
  Supervised Cognitive Runtime (SCR) - Multi-agent cognition runtime on BEAM.

  A fault-tolerant, persistent multi-agent system built on OTP principles.
  """

  def start(_type, _args) do
    SCR.Supervisor.start_link([])
  end
end
