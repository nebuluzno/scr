defmodule SCR.Message do
  @moduledoc """
  Structured message protocol for inter-agent communication.

  Messages are tuples with the following structure:
  {type, from, to, payload, timestamp, message_id}
  """

  @type message_type ::
          :task | :result | :critique | :spawn | :status | :ping | :pong | :stop | :error
  @type agent_id :: String.t()
  @type payload :: map()

  defstruct [:type, :from, :to, :payload, :timestamp, :message_id, :dedupe_key]

  @doc """
  Create a new message with a unique ID and current timestamp.
  """
  def new(type, from, to, payload \\ %{}, opts \\ []) do
    %__MODULE__{
      type: type,
      from: from,
      to: to,
      payload: payload,
      timestamp: DateTime.utc_now(),
      message_id: UUID.uuid4(),
      dedupe_key: Keyword.get(opts, :dedupe_key)
    }
  end

  @doc """
  Create a task message.
  """
  def task(from, to, task_data, opts \\ []) do
    dedupe_key =
      Keyword.get(opts, :dedupe_key) ||
        Map.get(task_data, :dedupe_key) ||
        Map.get(task_data, :task_id)

    new(:task, from, to, %{task: task_data}, dedupe_key: dedupe_key)
  end

  @doc """
  Create a result message.
  """
  def result(from, to, result_data) do
    new(:result, from, to, %{result: result_data})
  end

  @doc """
  Create a critique message.
  """
  def critique(from, to, critique_data) do
    new(:critique, from, to, %{critique: critique_data})
  end

  @doc """
  Create a spawn message for creating new agents.
  """
  def spawn(from, to, spawn_config) do
    new(:spawn, from, to, %{config: spawn_config})
  end

  @doc """
  Create a status message.
  """
  def status(from, to, status_data) do
    new(:status, from, to, %{status: status_data})
  end

  @doc """
  Create a stop message.
  """
  def stop(from, to, reason \\ %{reason: "normal"}) do
    new(:stop, from, to, reason)
  end

  @doc """
  Create an error message.
  """
  def error(from, to, error_data) do
    new(:error, from, to, %{error: error_data})
  end

  @doc """
  Create a ping message for heartbeat.
  """
  def ping(from, to) do
    new(:ping, from, to, %{})
  end

  @doc """
  Create a pong message for heartbeat response.
  """
  def pong(from, to) do
    new(:pong, from, to, %{})
  end

  @doc """
  Extract task from message payload.
  """
  def get_task(%__MODULE__{payload: %{task: task}}), do: task
  def get_task(_), do: nil

  @doc """
  Extract result from message payload.
  """
  def get_result(%__MODULE__{payload: %{result: result}}), do: result
  def get_result(_), do: nil

  @doc """
  Extract critique from message payload.
  """
  def get_critique(%__MODULE__{payload: %{critique: critique}}), do: critique
  def get_critique(_), do: nil

  @doc """
  Extract spawn config from message payload.
  """
  def get_spawn_config(%__MODULE__{payload: %{config: config}}), do: config
  def get_spawn_config(_), do: nil
end
