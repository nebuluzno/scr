defmodule SCR.Distributed do
  @moduledoc """
  Lightweight distributed runtime helpers for SCR.

  Provides cluster status, cross-node RPC helpers, remote health checks,
  and explicit agent handoff operations.
  """

  alias SCR.Distributed.NodeWatchdog
  alias SCR.Distributed.PeerManager

  @default_rpc_timeout_ms 5_000
  @trend_cache_key {:scr, :distributed, :placement_trends}

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
    pick_start_node_with_opts(nil, candidates)
  end

  @doc """
  Picks a placement node for a workload class (`cpu`, `io`, `external_api`, ...).
  """
  def pick_start_node_for_class(workload_class, candidates \\ nil) do
    pick_start_node_with_opts(workload_class, candidates)
  end

  defp pick_start_node_with_opts(workload_class, candidates) do
    nodes = candidates || healthy_cluster_nodes()

    healthy =
      if Process.whereis(NodeWatchdog), do: NodeWatchdog.filter_healthy(nodes), else: nodes

    opts =
      if is_nil(workload_class),
        do: %{},
        else: %{workload_class: workload_class}

    case placement_report(healthy, rpc_timeout_ms(), opts) do
      {:ok, [_ | _] = scored} ->
        eligible =
          Enum.reject(scored, &(node_backpressured_for_placement?(&1) or node_constrained?(&1)))

        case eligible do
          [_ | _] ->
            best = Enum.max_by(eligible, & &1.score)
            {:ok, best.node}

          [] ->
            if Enum.any?(scored, &node_backpressured_for_placement?/1) do
              {:error, :cluster_backpressured}
            else
              {:error, :cluster_constrained}
            end
        end

      _ ->
        {:error, :no_healthy_nodes}
    end
  end

  @doc """
  Returns per-node queue pressure snapshots used by scheduler decisions.
  """
  def queue_pressure_report(candidates \\ nil, timeout_ms \\ rpc_timeout_ms()) do
    nodes = candidates || healthy_cluster_nodes()

    report =
      Enum.map(nodes, fn node ->
        node_queue_pressure(node, timeout_ms)
      end)

    {:ok, report}
  end

  @doc """
  Returns true when cluster queue saturation exceeds configured thresholds.
  """
  def cluster_backpressured?(candidates \\ nil, timeout_ms \\ rpc_timeout_ms()) do
    if not enabled?() or not backpressure_enabled?() do
      false
    else
      with {:ok, [_ | _] = report} <- queue_pressure_report(candidates, timeout_ms) do
        utilizations = Enum.map(report, &Map.get(&1, :utilization, 1.0))
        cluster_utilization = Enum.sum(utilizations) / length(utilizations)
        max_utilization = Enum.max(utilizations)

        cluster_utilization >= backpressure_cluster_threshold() or
          max_utilization >= backpressure_max_node_utilization()
      else
        _ -> false
      end
    end
  end

  @doc """
  Returns weighted placement scores for candidate nodes.
  """
  def placement_report(candidates \\ nil, timeout_ms \\ rpc_timeout_ms(), opts \\ %{}) do
    nodes = candidates || healthy_cluster_nodes()

    if nodes == [] do
      {:ok, []}
    else
      report =
        Enum.map(nodes, fn node ->
          score_node(node, timeout_ms, opts)
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
    workload_class = extract_workload_class(init_arg)

    pick_node_result =
      if is_nil(workload_class),
        do: pick_start_node(),
        else: pick_start_node_for_class(workload_class)

    with {:ok, target_node} <- pick_node_result do
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

  defp score_node(node, timeout_ms, opts) do
    weights = placement_weights()
    constraints = placement_constraints()
    workload_class = Map.get(opts, :workload_class)
    workload = workload_score(node, workload_class, weights)
    pressure = node_queue_pressure(node, timeout_ms)
    queue_size = pressure.size
    queue_max_size = pressure.max_size
    queue_utilization = pressure.utilization
    queue_saturated = pressure.saturated
    agent_count = node_agent_count(node, timeout_ms)
    unhealthy_count = node_unhealthy_count(node, timeout_ms)
    trend = node_placement_trend(node, queue_size, agent_count, unhealthy_count)
    down_events = node_down_events(node)
    quarantined = quarantined_target?(node)
    max_agents_per_node = Map.get(constraints, :max_agents_per_node)
    max_queue_per_node = Map.get(constraints, :max_queue_per_node)
    agent_capacity_exceeded = constrained_count?(agent_count, max_agents_per_node)
    queue_capacity_exceeded = constrained_count?(queue_size, max_queue_per_node)
    constrained = agent_capacity_exceeded or queue_capacity_exceeded

    score =
      100.0 -
        queue_size * Map.get(weights, :queue_depth_weight, 1.0) -
        workload.penalty +
        workload.bonus -
        queue_utilization * Map.get(weights, :queue_utilization_weight, 30.0) -
        max(trend.queue_delta_per_sec, 0.0) * Map.get(weights, :queue_growth_weight, 10.0) -
        max(trend.agent_delta_per_sec, 0.0) * Map.get(weights, :agent_growth_weight, 5.0) -
        agent_count * Map.get(weights, :agent_count_weight, 1.0) -
        unhealthy_count * Map.get(weights, :unhealthy_weight, 15.0) -
        down_events * Map.get(weights, :down_event_weight, 5.0) -
        if(queue_saturated, do: Map.get(weights, :saturated_penalty, 40.0), else: 0.0) -
        if(constrained, do: Map.get(weights, :constraint_penalty, 500.0), else: 0.0) -
        if(quarantined, do: 1000.0, else: 0.0) +
        if(node == Node.self(), do: Map.get(weights, :local_bias, 2.0), else: 0.0)

    %{
      node: node,
      score: Float.round(score, 2),
      queue_size: queue_size,
      queue_max_size: queue_max_size,
      queue_utilization: queue_utilization,
      queue_saturated: queue_saturated,
      queue_growth_per_sec: trend.queue_delta_per_sec,
      agent_count: agent_count,
      agent_growth_per_sec: trend.agent_delta_per_sec,
      unhealthy_count: unhealthy_count,
      unhealthy_growth_per_sec: trend.unhealthy_delta_per_sec,
      recent_down_events: down_events,
      max_agents_per_node: max_agents_per_node,
      max_queue_per_node: max_queue_per_node,
      agent_capacity_exceeded: agent_capacity_exceeded,
      queue_capacity_exceeded: queue_capacity_exceeded,
      workload_class: workload_class,
      workload_compatible: workload.compatible,
      workload_penalty: workload.penalty,
      workload_bonus: workload.bonus,
      constrained: constrained,
      quarantined: quarantined
    }
  end

  defp node_queue_pressure(node, timeout_ms) do
    case rpc_call(node, SCR.TaskQueue, :stats, [], timeout_ms) do
      stats when is_map(stats) ->
        size = Map.get(stats, :size, 0)
        max_size = max(Map.get(stats, :max_size, 0), 1)
        utilization = min(size / max_size, 1.0)

        %{
          node: node,
          size: size,
          max_size: max_size,
          utilization: Float.round(utilization, 4),
          saturated: size >= max_size
        }

      _ ->
        %{
          node: node,
          size: 1000,
          max_size: 1000,
          utilization: 1.0,
          saturated: true
        }
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

  defp placement_constraints do
    distributed_config()
    |> Keyword.get(:placement_constraints, [])
    |> Enum.into(%{})
  end

  defp extract_workload_class(init_arg) when is_map(init_arg) do
    Map.get(init_arg, :workload_class) || Map.get(init_arg, "workload_class")
  end

  defp extract_workload_class(_), do: nil

  defp validate_handoff_target(source_node, target_node) do
    constraints = placement_constraints()
    pressure = node_queue_pressure(target_node, rpc_timeout_ms())
    target_agent_count = node_agent_count(target_node, rpc_timeout_ms())

    cond do
      source_node == target_node ->
        {:error, :same_node}

      target_node not in list_cluster_nodes() ->
        {:error, :target_not_connected}

      quarantined_target?(target_node) ->
        {:error, :target_quarantined}

      node_backpressured_for_handoff?(target_node) ->
        {:error, :target_backpressured}

      constrained_count?(target_agent_count, Map.get(constraints, :max_agents_per_node)) ->
        {:error, :target_agent_capacity_exceeded}

      constrained_count?(pressure.size, Map.get(constraints, :max_queue_per_node)) ->
        {:error, :target_queue_capacity_exceeded}

      true ->
        :ok
    end
  end

  defp node_backpressured_for_placement?(entry) do
    backpressure_enabled?() and
      Map.get(entry, :queue_utilization, 1.0) >= backpressure_max_node_utilization()
  end

  defp node_backpressured_for_handoff?(node) do
    if backpressure_enabled?() do
      node
      |> node_queue_pressure(rpc_timeout_ms())
      |> Map.get(:utilization, 1.0)
      |> Kernel.>=(backpressure_max_node_utilization())
    else
      false
    end
  end

  defp backpressure_enabled? do
    distributed_config()
    |> Keyword.get(:backpressure, [])
    |> Keyword.get(:enabled, true)
  end

  defp backpressure_cluster_threshold do
    distributed_config()
    |> Keyword.get(:backpressure, [])
    |> Keyword.get(:cluster_saturation_threshold, 0.85)
  end

  defp backpressure_max_node_utilization do
    distributed_config()
    |> Keyword.get(:backpressure, [])
    |> Keyword.get(:max_node_utilization, 0.98)
  end

  defp node_constrained?(entry) do
    Map.get(entry, :constrained, false) or not Map.get(entry, :workload_compatible, true)
  end

  defp constrained_count?(_value, nil), do: false
  defp constrained_count?(_value, value) when not is_integer(value), do: false
  defp constrained_count?(value, max_allowed) when is_integer(value), do: value >= max_allowed

  defp node_placement_trend(node, queue_size, agent_count, unhealthy_count) do
    now_ms = System.monotonic_time(:millisecond)
    history = :persistent_term.get(@trend_cache_key, %{})
    previous = Map.get(history, node)

    trend =
      case previous do
        %{
          ts_ms: ts_ms,
          queue_size: prev_queue,
          agent_count: prev_agents,
          unhealthy_count: prev_unhealthy
        }
        when now_ms > ts_ms ->
          elapsed_s = max((now_ms - ts_ms) / 1_000.0, 0.001)

          %{
            queue_delta_per_sec: Float.round((queue_size - prev_queue) / elapsed_s, 4),
            agent_delta_per_sec: Float.round((agent_count - prev_agents) / elapsed_s, 4),
            unhealthy_delta_per_sec:
              Float.round((unhealthy_count - prev_unhealthy) / elapsed_s, 4)
          }

        _ ->
          %{queue_delta_per_sec: 0.0, agent_delta_per_sec: 0.0, unhealthy_delta_per_sec: 0.0}
      end

    next_history =
      Map.put(history, node, %{
        ts_ms: now_ms,
        queue_size: queue_size,
        agent_count: agent_count,
        unhealthy_count: unhealthy_count
      })

    :persistent_term.put(@trend_cache_key, next_history)
    trend
  end

  defp quarantined_target?(target_node) do
    if Process.whereis(NodeWatchdog) do
      NodeWatchdog.quarantined?(target_node)
    else
      false
    end
  end

  defp workload_score(_node, nil, _weights) do
    %{compatible: true, penalty: 0.0, bonus: 0.0}
  end

  defp workload_score(node, workload_class, weights) do
    cfg =
      distributed_config()
      |> Keyword.get(:workload_routing, [])

    enabled = Keyword.get(cfg, :enabled, false)

    if not enabled do
      %{compatible: true, penalty: 0.0, bonus: 0.0}
    else
      classes = Keyword.get(cfg, :classes, %{})
      node_caps = Keyword.get(cfg, :node_capabilities, %{})
      local_caps = Keyword.get(cfg, :local_capabilities, [])
      strict = Keyword.get(cfg, :strict, false)
      required = Map.get(classes, to_string(workload_class), [])
      caps = node_capabilities_for(node, node_caps, local_caps)

      compatible =
        required == [] or Enum.all?(required, fn capability -> capability in caps end)

      bonus =
        if compatible do
          Map.get(weights, :workload_match_bonus, 10.0)
        else
          0.0
        end

      penalty =
        if compatible do
          0.0
        else
          if strict do
            Map.get(weights, :workload_incompatible_penalty, 2_000.0)
          else
            Map.get(weights, :workload_incompatible_penalty, 2_000.0) / 20.0
          end
        end

      %{compatible: compatible, penalty: penalty, bonus: bonus}
    end
  end

  defp node_capabilities_for(node, capabilities, local_capabilities) do
    by_atom = Map.get(capabilities, node, [])
    by_string = Map.get(capabilities, to_string(node), [])
    local = if node == Node.self(), do: local_capabilities, else: []

    (by_atom ++ by_string ++ local)
    |> Enum.uniq()
  end
end
