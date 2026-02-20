defmodule SCR.HealthCheck do
  @moduledoc """
  Periodic agent health checks with optional self-healing.
  """

  use GenServer
  require Logger

  @default_interval_ms 15_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def check_health(agent_id) when is_binary(agent_id) do
    case SCR.Supervisor.get_agent_status(agent_id) do
      {:ok, %{status: status}} when status in [:running, :idle, :processing] ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:unhealthy_status, status}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  catch
    :exit, reason -> {:error, {:unreachable, reason}}
  end

  def heal_agent(agent_id) when is_binary(agent_id) do
    case SCR.Supervisor.restart_agent(agent_id) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def run_once do
    GenServer.call(__MODULE__, :run_once)
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    cfg = Application.get_env(:scr, :health_check, [])
    interval_ms = Keyword.get(cfg, :interval_ms, @default_interval_ms)

    state = %{
      interval_ms: interval_ms,
      auto_heal: Keyword.get(cfg, :auto_heal, true),
      checks: 0,
      unhealthy: 0,
      healed: 0,
      last_run_at: nil
    }

    Process.send_after(self(), :scan, interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:scan, state) do
    next_state = do_scan(state)
    Process.send_after(self(), :scan, state.interval_ms)
    {:noreply, next_state}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    next_state = do_scan(state)
    {:reply, :ok, next_state}
  end

  def handle_call(:stats, _from, state), do: {:reply, state, state}

  defp do_scan(state) do
    agents = SCR.Supervisor.list_agents()

    Enum.reduce(
      agents,
      %{state | checks: state.checks + length(agents), last_run_at: DateTime.utc_now()},
      fn agent_id, acc ->
        case check_health(agent_id) do
          :ok ->
            acc

          {:error, reason} ->
            Logger.warning("[health] unhealthy agent=#{agent_id} reason=#{inspect(reason)}")

            healed? =
              if acc.auto_heal do
                case heal_agent(agent_id) do
                  :ok ->
                    Logger.warning("[health] auto-healed agent=#{agent_id}")
                    true

                  {:error, heal_reason} ->
                    Logger.warning(
                      "[health] heal failed agent=#{agent_id} reason=#{inspect(heal_reason)}"
                    )

                    false
                end
              else
                false
              end

            %{
              acc
              | unhealthy: acc.unhealthy + 1,
                healed: acc.healed + if(healed?, do: 1, else: 0)
            }
        end
      end
    )
  end
end
