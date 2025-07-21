defmodule VsmEventBus.Core.EventRouter do
  @moduledoc """
  VSM-aware event routing engine.
  
  This module implements intelligent routing based on VSM principles,
  ensuring proper communication flow between subsystems according to
  the Viable System Model architecture.
  """
  
  use GenServer
  require Logger
  
  alias VsmEventBus.Core.EventBus
  
  @vsm_routing_rules %{
    # Command channel: Top-down hierarchical flow
    command_channel: %{
      :system5 => [:system4, :system3, :system1],
      :system4 => [:system3, :system1],
      :system3 => [:system1],
      :system1 => []  # System 1 doesn't send commands
    },
    
    # Coordination channel: Peer-to-peer between S2 and S1
    coordination_channel: %{
      :system2 => [:system1],
      :system1 => [:system2]
    },
    
    # Audit channel: S3* to/from S1
    audit_channel: %{
      :system3_star => [:system1],
      :system1 => [:system3_star]
    },
    
    # Algedonic channel: Emergency bypass S1 -> S5
    algedonic_channel: %{
      :system1 => [:system5],
      :system2 => [:system5],
      :system3 => [:system5]
    },
    
    # Resource bargain: S1 <-> S3 negotiations
    resource_bargain_channel: %{
      :system1 => [:system3],
      :system3 => [:system1]
    }
  }
  
  defstruct [
    routing_rules: @vsm_routing_rules,
    route_cache: %{},
    invalid_routes: [],
    stats: %{routed: 0, blocked: 0, cached: 0}
  ]
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Validates if a route is allowed according to VSM principles.
  
  ## Examples
  
      iex> VsmEventBus.Core.EventRouter.validate_route(:system5, :system1, :command_channel)
      {:ok, :direct}
      
      iex> VsmEventBus.Core.EventRouter.validate_route(:system1, :system5, :command_channel)
      {:error, :invalid_vsm_flow}
  """
  def validate_route(source, target, channel) do
    GenServer.call(__MODULE__, {:validate_route, source, target, channel})
  end
  
  @doc """
  Finds the optimal routing path between subsystems.
  """
  def find_route(source, target, channel, opts \\ []) do
    GenServer.call(__MODULE__, {:find_route, source, target, channel, opts})
  end
  
  @doc """
  Gets routing statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Clears the routing cache.
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end
  
  ## Server Implementation
  
  @impl true
  def init(opts) do
    custom_rules = Keyword.get(opts, :routing_rules, %{})
    routing_rules = Map.merge(@vsm_routing_rules, custom_rules)
    
    Logger.info("VSM Event Router started with #{map_size(routing_rules)} channel rules")
    
    state = %__MODULE__{
      routing_rules: routing_rules
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:validate_route, source, target, channel}, _from, state) do
    cache_key = {source, target, channel}
    
    result = case Map.get(state.route_cache, cache_key) do
      nil ->
        validation_result = do_validate_route(source, target, channel, state.routing_rules)
        new_cache = Map.put(state.route_cache, cache_key, validation_result)
        new_state = %{state | route_cache: new_cache}
        
        case validation_result do
          {:ok, _} -> 
            new_stats = Map.update!(state.stats, :routed, &(&1 + 1))
            {:reply, validation_result, %{new_state | stats: new_stats}}
          {:error, _} -> 
            new_stats = Map.update!(state.stats, :blocked, &(&1 + 1))
            {:reply, validation_result, %{new_state | stats: new_stats}}
        end
        
      cached_result ->
        new_stats = Map.update!(state.stats, :cached, &(&1 + 1))
        {:reply, cached_result, %{state | stats: new_stats}}
    end
    
    result
  end
  
  @impl true
  def handle_call({:find_route, source, target, channel, opts}, _from, state) do
    case validate_route_internal(source, target, channel, state.routing_rules) do
      {:ok, :direct} ->
        {:reply, {:ok, [target]}, state}
        
      {:ok, :hierarchical} ->
        path = find_hierarchical_path(source, target, channel, state.routing_rules)
        {:reply, {:ok, path}, state}
        
      {:error, reason} ->
        # Try to find alternative routes if requested
        if Keyword.get(opts, :find_alternative, false) do
          case find_alternative_route(source, target, channel, state.routing_rules) do
            {:ok, path} -> {:reply, {:ok, path}, state}
            {:error, _} -> {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      cache_size: map_size(state.route_cache),
      invalid_routes_count: length(state.invalid_routes)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:clear_cache, _from, state) do
    new_state = %{state | route_cache: %{}}
    {:reply, :ok, new_state}
  end
  
  ## Private Functions
  
  defp do_validate_route(source, target, channel, routing_rules) do
    channel_rules = Map.get(routing_rules, channel, %{})
    allowed_targets = Map.get(channel_rules, source, [])
    
    cond do
      target in allowed_targets ->
        {:ok, :direct}
        
      is_hierarchical_route?(source, target, channel, routing_rules) ->
        {:ok, :hierarchical}
        
      channel == :algedonic_channel and is_emergency_route?(source, target) ->
        {:ok, :emergency}
        
      target == :broadcast ->
        {:ok, :broadcast}
        
      true ->
        {:error, :invalid_vsm_flow}
    end
  end
  
  defp validate_route_internal(source, target, channel, routing_rules) do
    do_validate_route(source, target, channel, routing_rules)
  end
  
  defp is_hierarchical_route?(source, target, :command_channel, routing_rules) do
    # For command channel, check if there's a valid downward path
    command_rules = Map.get(routing_rules, :command_channel, %{})
    find_path_downward(source, target, command_rules, [source]) != nil
  end
  
  defp is_hierarchical_route?(_source, _target, _channel, _routing_rules), do: false
  
  defp is_emergency_route?(source, :system5) when source in [:system1, :system2, :system3], do: true
  defp is_emergency_route?(_source, _target), do: false
  
  defp find_hierarchical_path(source, target, :command_channel, routing_rules) do
    command_rules = Map.get(routing_rules, :command_channel, %{})
    
    case find_path_downward(source, target, command_rules, [source]) do
      nil -> []
      path -> Enum.drop(path, 1)  # Remove source from path
    end
  end
  
  defp find_hierarchical_path(_source, _target, _channel, _routing_rules), do: []
  
  defp find_path_downward(current, target, rules, path) do
    if current == target do
      Enum.reverse(path)
    else
      allowed_targets = Map.get(rules, current, [])
      
      allowed_targets
      |> Enum.find_value(fn next_target ->
        if next_target not in path do  # Avoid cycles
          find_path_downward(next_target, target, rules, [next_target | path])
        end
      end)
    end
  end
  
  defp find_alternative_route(source, target, channel, _routing_rules) do
    # For now, simple implementation - could be enhanced with graph algorithms
    case channel do
      :command_channel ->
        # Try routing through System 3 as intermediary
        if source in [:system4, :system5] and target == :system1 do
          {:ok, [:system3, :system1]}
        else
          {:error, :no_alternative}
        end
        
      _ ->
        {:error, :no_alternative}
    end
  end
end