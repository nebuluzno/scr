defmodule SCR.Distributed do
  @moduledoc """
  Lightweight distributed runtime helpers for SCR.

  Provides cluster status, cross-node RPC helpers, remote health checks,
  and explicit agent handoff operations.
  """

  alias SCR.Distributed.NodeWatchdog
  alias SCR.Distributed.PeerManager

  @default_rpc_timeout_ms 5_000

  @type rpc_error :: {:error, {:rpc_failed, term()}}

  @doc """
  Returns true when distributed mode is enabled.
  """
  def enabled? do
    cfg = distributed_config()
    Keyword.get(cfg, :enabled, false)
  end

  @doc """
  Returns local node/distributed status including peer-manager state.
  """
  def status do
    peer_status =
      if Process.whereis(PeerManager) do
        PeerManager.status()
      else
        %{
          enabled: false,
          configured_peers: [],
          connected_peers: [],
          last_connect_results: %{}
        }
      end

    watchdog_status =
      if Process.whereis(NodeWatchdog) do
        NodeWatchdog.status()
      else
        %{enabled: false, quarantined_nodes: %{}}
      end

    %{
      node: Node.self(),
      node_alive: Node.alive?(),
      connected_nodes: Node.list(),
      peer_manager: peer_status,
      watchdog: watchdog_status
    }
  end

  @doc """
  Triggers an immediate peer-connect cycle.
  """
  def connect_peers do
    if Process.whereis(PeerManager) do
      PeerManager.connect_now()
    else
      {:error, :peer_manager_not_started}
    end
  end

  @doc """
  Lists the known cluster nodes (self + connected peers).
  """
  def list_cluster_nodes do
    [Node.self() | Node.list()]
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns cluster nodes minus any currently quarantined nodes.
  """
  def healthy_cluster_nodes do
    nodes = list_cluster_nodes()

    if Process.whereis(NodeWatchdog) do
      NodeWatchdog.filter_healthy(nodes)
    else
      nodes
    end
  end

  @doc """
  Picks a placement node for new work, skipping quarantined nodes.
  """
  def pick_start_node(candidates \\ nil) do
    nodes = candidates || healthy_cluster_nodes()

    healthy =
      if Process.whereis(NodeWatchdog), do: NodeWatchdog.filter_healthy(nodes), else: nodes

    case placement_report(healthy) do
      {:ok, [_ | _] = scored} ->
        best = Enum.max_by(scored, & &1.score)
        {:ok, best.node}

      _ ->
        {:error, :no_healthy_nodes}
    end
  end

  @doc """
  Returns weighted placement scores for candidate nodes.
  """
  def placement_report(candidates \\ nil, timeout_ms \\ rpc_timeout_ms()) do
    nodes = candidates || healthy_cluster_nodes()

    if nodes == [] do
      {:ok, []}
    else
      report =
        Enum.map(nodes, fn node ->
          score_node(node, timeout_ms)
        end)

      {:ok, report}
    end
  end

  @doc """
  Lists agent ids on the given node.
  """
  def list_agents_on(node, timeout_ms \\ rpc_timeout_ms()) when is_atom(node) do
    case rpc_call(node, SCR.Supervisor, :list_agents, [], timeout_ms) do
      {:error, _} = error -> error
      agents when is_list(agents) -> {:ok, agents}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  @doc """
  Lists agents across all currently known nodes.
  """
  def list_cluster_agents(timeout_ms \\ rpc_timeout_ms()) do
    agents_by_node =
      Enum.reduce(list_cluster_nodes(), %{}, fn node, acc ->
        result =
          case list_agents_on(node, timeout_ms) do
            {:ok, agents} -> agents
            {:error, _} = error -> error
          end

        Map.put(acc, node, result)
      end)

    {:ok, agents_by_node}
  end

  @doc """
  Starts an agent on the given node.
  """
  def start_agent_on(
        node,
        agent_id,
        agent_type,
        module,
        init_arg \\ %{},
        timeout_ms \\ rpc_timeout_ms()
      )
      when is_atom(node) do
    rpc_call(
      node,
      SCR.Supervisor,
      :start_agent,
      [agent_id, agent_type, module, init_arg],
      timeout_ms
    )
  end

  @doc """
  Starts an agent using watchdog-aware node selection.
  """
  def start_agent(agent_id, agent_type, module, init_arg \\ %{}, timeout_ms \\ rpc_timeout_ms()) do
    with {:ok, target_node} <- pick_start_node() do
      case start_agent_on(target_node, agent_id, agent_type, module, init_arg, timeout_ms) do
        {:ok, _pid} -> {:ok, %{node: target_node, agent_id: agent_id}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns the stored start spec for an agent from the given node.
  """
  def get_agent_spec_on(node, agent_id, timeout_ms \\ rpc_timeout_ms()) when is_atom(node) do
    rpc_call(node, SCR.Supervisor, :get_agent_spec, [agent_id], timeout_ms)
  end

  @doc """
  Stops an agent on the given node.
  """
  def stop_agent_on(node, agent_id, timeout_ms \\ rpc_timeout_ms()) when is_atom(node) do
    rpc_call(node, SCR.Supervisor, :stop_agent, [agent_id], timeout_ms)
  end

  @doc """
  Fetches an agent status from the given node.
  """
  def get_agent_status_on(node, agent_id, timeout_ms \\ rpc_timeout_ms()) when is_atom(node) do
    rpc_call(node, SCR.Supervisor, :get_agent_status, [agent_id], timeout_ms)
  end

  @doc """
  Runs SCR health-check logic for one agent on the given node.
  """
  def check_agent_health_on(node, agent_id, timeout_ms \\ rpc_timeout_ms()) when is_atom(node) do
    rpc_call(node, SCR.HealthCheck, :check_health, [agent_id], timeout_ms)
  end

  @doc """
  Runs health checks across all visible nodes and returns per-node summaries.
  """
  def check_cluster_health(timeout_ms \\ rpc_timeout_ms()) do
    summaries =
      Enum.reduce(list_cluster_nodes(), %{}, fn node, acc ->
        summary =
          with {:ok, agents} <- list_agents_on(node, timeout_ms) do
            unhealthy =
              Enum.reduce(agents, [], fn agent_id, list ->
                case check_agent_health_on(node, agent_id, timeout_ms) do
                  :ok -> list
                  {:error, reason} -> [%{agent_id: agent_id, reason: reason} | list]
                end
              end)
              |> Enum.reverse()

            %{
              ok: unhealthy == [],
              agent_count: length(agents),
              unhealthy: unhealthy
            }
          else
            {:error, reason} ->
              %{ok: false, error: reason}
          end

        Map.put(acc, node, summary)
      end)

    {:ok, summaries}
  end

  @doc """
  Moves an agent from its current node to a target node.
  """
  def handoff_agent(agent_id, target_node, timeout_ms \\ rpc_timeout_ms())
      when is_binary(agent_id) and is_atom(target_node) do
    with {:ok, pid} <- SCR.Supervisor.get_agent_pid(agent_id),
         source_node <- node(pid),
         :ok <- validate_handoff_target(source_node, target_node),
         {:ok, %{agent_type: agent_type, module: module, init_arg: init_arg}} <-
           get_agent_spec_on(source_node, agent_id, timeout_ms),
         {:ok, _pid} <-
           start_agent_on(target_node, agent_id, agent_type, module, init_arg, timeout_ms),
         :ok <- stop_agent_on(source_node, agent_id, timeout_ms) do
      if Process.whereis(SCR.Distributed.SpecRegistry) do
        SCR.Distributed.SpecRegistry.claim(agent_id, target_node)
      end

      {:ok, %{agent_id: agent_id, from: source_node, to: target_node}}
    end
  end

  defp rpc_call(node, module, fun, args, timeout_ms) do
    if node == Node.self() do
      try do
        apply(module, fun, args)
      catch
        :exit, reason -> {:error, {:rpc_failed, reason}}
      end
    else
      case :rpc.call(node, module, fun, args, timeout_ms) do
        {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
        other -> other
      end
    end
  end

  defp rpc_timeout_ms do
    cfg = distributed_config()
    Keyword.get(cfg, :rpc_timeout_ms, @default_rpc_timeout_ms)
  end

  defp distributed_config do
    SCR.ConfigCache.get(:distributed, [])
  end

  defp score_node(node, timeout_ms) do
    weights = placement_weights()
    queue_size = node_queue_size(node, timeout_ms)
    agent_count = node_agent_count(node, timeout_ms)
    unhealthy_count = node_unhealthy_count(node, timeout_ms)
    down_events = node_down_events(node)
    quarantined = quarantined_target?(node)

    score =
      100.0 -
        queue_size * Map.get(weights, :queue_depth_weight, 1.0) -
        agent_count * Map.get(weights, :agent_count_weight, 1.0) -
        unhealthy_count * Map.get(weights, :unhealthy_weight, 15.0) -
        down_events * Map.get(weights, :down_event_weight, 5.0) -
        if(quarantined, do: 1000.0, else: 0.0) +
        if(node == Node.self(), do: Map.get(weights, :local_bias, 2.0), else: 0.0)

    %{
      node: node,
      score: Float.round(score, 2),
      queue_size: queue_size,
      agent_count: agent_count,
      unhealthy_count: unhealthy_count,
      recent_down_events: down_events,
      quarantined: quarantined
    }
  end

  defp node_queue_size(node, timeout_ms) do
    case rpc_call(node, SCR.TaskQueue, :stats, [], timeout_ms) do
      stats when is_map(stats) -> Map.get(stats, :size, 0)
      _ -> 1000
    end
  end

  defp node_agent_count(node, timeout_ms) do
    case list_agents_on(node, timeout_ms) do
      {:ok, agents} -> length(agents)
      _ -> 1000
    end
  end

  defp node_unhealthy_count(node, timeout_ms) do
    case list_agents_on(node, timeout_ms) do
      {:ok, agents} ->
        Enum.reduce(agents, 0, fn agent_id, acc ->
          case check_agent_health_on(node, agent_id, timeout_ms) do
            :ok -> acc
            {:error, _} -> acc + 1
          end
        end)

      _ ->
        1000
    end
  end

  defp node_down_events(node) do
    if Process.whereis(NodeWatchdog) do
      NodeWatchdog.status()
      |> Map.get(:recent_down_events, %{})
      |> Map.get(node, 0)
    else
      0
    end
  end

  defp placement_weights do
    cfg = distributed_config()

    cfg
    |> Keyword.get(:placement_weights, [])
    |> Enum.into(%{})
  end

  defp validate_handoff_target(source_node, target_node) do
    cond do
      source_node == target_node -> {:error, :same_node}
      target_node not in list_cluster_nodes() -> {:error, :target_not_connected}
      quarantined_target?(target_node) -> {:error, :target_quarantined}
      true -> :ok
    end
  end

  defp quarantined_target?(target_node) do
    if Process.whereis(NodeWatchdog) do
      NodeWatchdog.quarantined?(target_node)
    else
      false
    end
  end
end
