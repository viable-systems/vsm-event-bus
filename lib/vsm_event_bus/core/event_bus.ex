defmodule VsmEventBus.Core.EventBus do
  @moduledoc """
  Core VSM Event Bus GenServer.
  
  This module provides the central coordination point for all VSM events,
  implementing the event bus pattern with VSM-aware routing and filtering.
  """
  
  use GenServer
  require Logger
  
  alias VsmEventBus.Core.{EventRouter, EventStore}
  alias VsmEventBus.Telemetry.EventMetrics
  
  @type event_id :: binary()
  @type subsystem :: :system1 | :system2 | :system3 | :system3_star | :system4 | :system5
  @type channel :: :command_channel | :coordination_channel | :audit_channel | :algedonic_channel | :resource_bargain_channel
  @type event_type :: atom()
  
  @type vsm_event :: %{
    id: event_id(),
    source: subsystem(),
    target: subsystem() | [subsystem()] | :broadcast,
    channel: channel(),
    type: event_type(),
    payload: map(),
    timestamp: DateTime.t(),
    metadata: map(),
    correlation_id: binary() | nil
  }
  
  @type subscription :: %{
    subscriber: pid(),
    filter: function() | nil,
    channel: channel() | :all,
    source: subsystem() | :all,
    target: subsystem() | :all
  }
  
  defstruct [
    :node_id,
    subscriptions: %{},
    events: [],
    event_count: 0,
    config: %{}
  ]
  
  ## Client API
  
  @doc """
  Starts the VSM Event Bus.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Publishes an event to the VSM event bus.
  
  ## Examples
  
      iex> event = %{
      ...>   source: :system1,
      ...>   target: :system3,
      ...>   channel: :command_channel,
      ...>   type: :resource_request,
      ...>   payload: %{resource: :cpu, amount: 0.2}
      ...> }
      iex> VsmEventBus.Core.EventBus.publish(event)
      {:ok, event_id}
  """
  def publish(event_data, opts \\ []) do
    event = build_event(event_data, opts)
    
    :telemetry.execute(
      [:vsm_event_bus, :event, :publish],
      %{count: 1},
      %{channel: event.channel, type: event.type, source: event.source}
    )
    
    GenServer.call(__MODULE__, {:publish, event})
  end
  
  @doc """
  Subscribes to VSM events with optional filtering.
  
  ## Examples
  
      iex> # Subscribe to all algedonic alerts
      iex> VsmEventBus.Core.EventBus.subscribe(
      ...>   channel: :algedonic_channel,
      ...>   filter: fn event -> event.payload.severity == :critical end
      ...> )
      {:ok, subscription_id}
      
      iex> # Subscribe to all events from System 1
      iex> VsmEventBus.Core.EventBus.subscribe(source: :system1)
      {:ok, subscription_id}
  """
  def subscribe(opts \\ []) do
    subscription = build_subscription(opts)
    GenServer.call(__MODULE__, {:subscribe, subscription})
  end
  
  @doc """
  Unsubscribes from VSM events.
  """
  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end
  
  @doc """
  Gets current bus statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  @doc """
  Lists all active subscriptions.
  """
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end
  
  ## Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, generate_node_id())
    config = build_config(opts)
    
    Logger.info("VSM Event Bus started on node #{node_id}")
    
    state = %__MODULE__{
      node_id: node_id,
      config: config
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:publish, event}, _from, state) do
    # Store event for persistence/replay
    :ok = EventStore.store_event(event)
    
    # Route event to subscribers
    delivered_count = route_event(event, state.subscriptions)
    
    # Update state
    new_state = %{state | 
      events: [event | Enum.take(state.events, 999)],
      event_count: state.event_count + 1
    }
    
    {:reply, {:ok, event.id, delivered_count}, new_state}
  end
  
  @impl true
  def handle_call({:subscribe, subscription}, {pid, _ref}, state) do
    subscription_id = generate_subscription_id()
    subscription_with_pid = %{subscription | subscriber: pid}
    
    # Monitor subscriber process
    Process.monitor(pid)
    
    new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription_with_pid)
    new_state = %{state | subscriptions: new_subscriptions}
    
    :telemetry.execute(
      [:vsm_event_bus, :event, :subscribe],
      %{count: 1},
      %{channel: subscription.channel, source: subscription.source}
    )
    
    {:reply, {:ok, subscription_id}, new_state}
  end
  
  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    new_subscriptions = Map.delete(state.subscriptions, subscription_id)
    new_state = %{state | subscriptions: new_subscriptions}
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      node_id: state.node_id,
      total_events: state.event_count,
      active_subscriptions: map_size(state.subscriptions),
      recent_events: length(state.events),
      uptime: :erlang.monotonic_time(:second)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = 
      state.subscriptions
      |> Enum.map(fn {id, sub} -> 
        %{
          id: id,
          channel: sub.channel,
          source: sub.source,
          target: sub.target,
          has_filter: sub.filter != nil
        }
      end)
    
    {:reply, subscriptions, state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriptions for dead processes
    new_subscriptions = 
      state.subscriptions
      |> Enum.reject(fn {_id, sub} -> sub.subscriber == pid end)
      |> Map.new()
    
    new_state = %{state | subscriptions: new_subscriptions}
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp build_event(event_data, opts) do
    %{
      id: Keyword.get(opts, :id, generate_event_id()),
      source: Map.get(event_data, :source),
      target: Map.get(event_data, :target),
      channel: Map.get(event_data, :channel),
      type: Map.get(event_data, :type),
      payload: Map.get(event_data, :payload, %{}),
      timestamp: DateTime.utc_now(),
      metadata: Map.get(event_data, :metadata, %{}),
      correlation_id: Map.get(event_data, :correlation_id)
    }
  end
  
  defp build_subscription(opts) do
    %{
      subscriber: nil,  # Will be set in handle_call
      filter: Keyword.get(opts, :filter),
      channel: Keyword.get(opts, :channel, :all),
      source: Keyword.get(opts, :source, :all),
      target: Keyword.get(opts, :target, :all)
    }
  end
  
  defp build_config(opts) do
    %{
      max_events_history: Keyword.get(opts, :max_events_history, 1000),
      enable_persistence: Keyword.get(opts, :enable_persistence, true),
      enable_clustering: Keyword.get(opts, :enable_clustering, false)
    }
  end
  
  defp route_event(event, subscriptions) do
    :telemetry.execute(
      [:vsm_event_bus, :event, :route],
      %{count: 1},
      %{channel: event.channel, target_type: target_type(event.target)}
    )
    
    subscriptions
    |> Enum.filter(fn {_id, sub} -> matches_subscription?(event, sub) end)
    |> Enum.map(fn {_id, sub} -> deliver_event(event, sub) end)
    |> Enum.count(& &1 == :ok)
  end
  
  defp matches_subscription?(event, subscription) do
    channel_match?(event.channel, subscription.channel) and
    source_match?(event.source, subscription.source) and
    target_match?(event.target, subscription.target) and
    filter_match?(event, subscription.filter)
  end
  
  defp channel_match?(_channel, :all), do: true
  defp channel_match?(channel, channel), do: true
  defp channel_match?(_, _), do: false
  
  defp source_match?(_source, :all), do: true
  defp source_match?(source, source), do: true
  defp source_match?(_, _), do: false
  
  defp target_match?(_target, :all), do: true
  defp target_match?(target, target), do: true
  defp target_match?(targets, target) when is_list(targets), do: target in targets
  defp target_match?(:broadcast, _), do: true
  defp target_match?(_, _), do: false
  
  defp filter_match?(_event, nil), do: true
  defp filter_match?(event, filter) when is_function(filter, 1) do
    try do
      filter.(event)
    rescue
      _ -> false
    end
  end
  defp filter_match?(_, _), do: false
  
  defp deliver_event(event, subscription) do
    try do
      send(subscription.subscriber, {:vsm_event, event})
      :ok
    rescue
      _ -> :error
    end
  end
  
  defp target_type(target) when is_atom(target), do: :single
  defp target_type(target) when is_list(target), do: :multiple
  defp target_type(:broadcast), do: :broadcast
  
  defp generate_node_id do
    "node_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp generate_event_id do
    "evt_#{UUID.uuid4()}"
  end
  
  defp generate_subscription_id do
    "sub_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end