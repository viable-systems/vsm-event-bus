defmodule VsmEventBus.Adapters.VSMChannels do
  @moduledoc """
  Adapter for integrating VSM Event Bus with VSM Core channels.
  
  This module bridges VSM Core's channel system with the event bus,
  allowing seamless integration and message transformation.
  """
  
  use GenServer
  require Logger
  
  alias VsmEventBus.Core.{EventBus, EventRouter}
  
  @vsm_channels [
    :command_channel,
    :coordination_channel,
    :audit_channel,
    :algedonic_channel,
    :resource_bargain_channel
  ]
  
  defstruct [
    :node_id,
    subscriptions: %{},
    message_transforms: %{},
    stats: %{messages_transformed: 0, events_published: 0}
  ]
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Publishes a VSM Core message as an event.
  """
  def publish_message(message) do
    GenServer.cast(__MODULE__, {:publish_message, message})
  end
  
  @doc """
  Subscribes to events and transforms them back to VSM messages.
  """
  def subscribe_to_events(channel, target_pid) do
    GenServer.call(__MODULE__, {:subscribe_to_events, channel, target_pid})
  end
  
  @doc """
  Gets adapter statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, "vsm_adapter_#{:rand.uniform(1000)}")
    
    Logger.info("VSM Channels Adapter started on node #{node_id}")
    
    # Subscribe to all VSM events
    {:ok, _sub_id} = EventBus.subscribe(channel: :all)
    
    state = %__MODULE__{
      node_id: node_id,
      message_transforms: build_message_transforms()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:publish_message, message}, state) do
    # Transform VSM Core message to event bus event
    case transform_message_to_event(message) do
      {:ok, event_data} ->
        {:ok, event_id, _count} = EventBus.publish(event_data)
        
        Logger.debug("Transformed VSM message #{message.id} to event #{event_id}")
        
        new_stats = update_in(state.stats.messages_transformed, &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}
        
      {:error, reason} ->
        Logger.warning("Failed to transform VSM message: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_call({:subscribe_to_events, channel, target_pid}, _from, state) do
    subscription_opts = if channel == :all do
      []
    else
      [channel: channel]
    end
    
    case EventBus.subscribe(subscription_opts) do
      {:ok, subscription_id} ->
        new_subscriptions = Map.put(state.subscriptions, subscription_id, %{
          channel: channel,
          target_pid: target_pid
        })
        
        {:reply, {:ok, subscription_id}, %{state | subscriptions: new_subscriptions}}
        
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      node_id: state.node_id,
      active_subscriptions: map_size(state.subscriptions)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info({:vsm_event, event}, state) do
    # Transform event back to VSM Core message format if needed
    case transform_event_to_message(event) do
      {:ok, message} ->
        # Broadcast to subscribed processes
        broadcast_to_subscribers(message, event.channel, state.subscriptions)
        
        new_stats = update_in(state.stats.events_published, &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}
        
      {:error, reason} ->
        Logger.debug("Skipping event transformation: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  ## Private Functions
  
  defp build_message_transforms do
    %{
      # Define any custom message transformations here
      default: &default_transform/1
    }
  end
  
  defp transform_message_to_event(message) do
    # Convert VSM Core Message struct to event bus format
    event_data = %{
      source: message.from,
      target: message.to,
      channel: message.channel,
      type: message.type,
      payload: Map.merge(message.payload || %{}, %{
        original_message_id: message.id,
        vsm_message: true
      }),
      metadata: Map.merge(message.metadata || %{}, %{
        transformed_from: :vsm_core_message,
        timestamp: message.timestamp
      }),
      correlation_id: message.correlation_id
    }
    
    {:ok, event_data}
  rescue
    error ->
      {:error, {:transform_failed, error}}
  end
  
  defp transform_event_to_message(event) do
    # Only transform events that originated from VSM Core messages
    if get_in(event.payload, [:vsm_message]) do
      message = %{
        id: event.id,
        from: event.source,
        to: event.target,
        channel: event.channel,
        type: event.type,
        payload: Map.drop(event.payload, [:original_message_id, :vsm_message]),
        timestamp: event.timestamp,
        metadata: event.metadata,
        correlation_id: event.correlation_id
      }
      
      {:ok, message}
    else
      {:error, :not_vsm_message}
    end
  end
  
  defp default_transform(data), do: data
  
  defp broadcast_to_subscribers(message, channel, subscriptions) do
    subscriptions
    |> Enum.filter(fn {_id, sub} -> 
      sub.channel == :all or sub.channel == channel
    end)
    |> Enum.each(fn {_id, sub} ->
      try do
        send(sub.target_pid, {:vsm_message, message})
      rescue
        _ -> :ok  # Ignore dead processes
      end
    end)
  end
end