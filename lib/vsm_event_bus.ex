defmodule VsmEventBus do
  @moduledoc """
  VSM Event Bus - Centralized event coordination for Viable System Model implementations.
  
  The VSM Event Bus provides a centralized, scalable event coordination system specifically
  designed for Viable System Model (VSM) architectures. It implements VSM-aware routing,
  filtering, and persistence while supporting distributed coordination via Phoenix PubSub
  and libcluster.
  
  ## Features
  
  - **VSM-Aware Routing**: Understands VSM subsystem communication patterns
  - **Phoenix PubSub Integration**: Scalable, distributed event handling
  - **Event Persistence**: Store and replay events for audit and recovery
  - **Real-time Monitoring**: Comprehensive telemetry and performance metrics
  - **Clustering Support**: Automatic failover and distributed coordination
  
  ## Quick Start
  
      # Publishing events
      event = %{
        source: :system1,
        target: :system3,
        channel: :resource_bargain_channel,
        type: :resource_request,
        payload: %{resource: :cpu, amount: 0.3}
      }
      
      {:ok, event_id, delivered_count} = VsmEventBus.publish(event)
      
      # Subscribing to events
      {:ok, subscription_id} = VsmEventBus.subscribe(
        channel: :algedonic_channel,
        filter: fn event -> event.payload.severity == :critical end
      )
      
      # Receiving events
      receive do
        {:vsm_event, event} -> handle_event(event)
      end
  
  ## VSM Channel Support
  
  The event bus supports all standard VSM communication channels:
  
  - `:command_channel` - Hierarchical command flow (S5 → S4 → S3 → S1)
  - `:coordination_channel` - Anti-oscillatory coordination (S2 ↔ S1)
  - `:audit_channel` - Audit communications (S3* ↔ S1)  
  - `:algedonic_channel` - Emergency alerts (S1 → S5)
  - `:resource_bargain_channel` - Resource negotiations (S1 ↔ S3)
  
  ## Event Structure
  
  All events follow a consistent structure:
  
      %{
        id: "evt_uuid",
        source: :system1,
        target: :system3,
        channel: :command_channel,
        type: :scale_operation,
        payload: %{...},
        timestamp: ~U[2025-01-21 01:00:00Z],
        metadata: %{...},
        correlation_id: "correlation_uuid"
      }
  """
  
  alias VsmEventBus.Core.{EventBus, EventRouter, EventStore}
  alias VsmEventBus.Adapters.VSMChannels
  alias VsmEventBus.Telemetry.EventMetrics
  
  @type subsystem :: :system1 | :system2 | :system3 | :system3_star | :system4 | :system5
  @type channel :: :command_channel | :coordination_channel | :audit_channel | :algedonic_channel | :resource_bargain_channel
  @type event_type :: atom()
  @type event_id :: binary()
  @type subscription_id :: binary()
  
  @type event :: %{
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
  
  ## Public API
  
  @doc """
  Publishes an event to the VSM event bus.
  
  ## Parameters
  
  - `event_data` - Map containing event information
  - `opts` - Optional parameters (`:id`, `:correlation_id`, etc.)
  
  ## Examples
  
      # Simple command event
      {:ok, event_id, delivered} = VsmEventBus.publish(%{
        source: :system3,
        target: :system1,
        channel: :command_channel,
        type: :scale_operation,
        payload: %{target_capacity: 150}
      })
      
      # Algedonic alert
      {:ok, event_id, delivered} = VsmEventBus.publish(%{
        source: :system1,
        target: :system5,
        channel: :algedonic_channel,
        type: :emergency_alert,
        payload: %{
          severity: :critical,
          signal: :pain,
          description: "Database connection pool exhausted"
        }
      })
      
      # Broadcast event
      {:ok, event_id, delivered} = VsmEventBus.publish(%{
        source: :system4,
        target: :broadcast,
        channel: :command_channel,
        type: :system_announcement,
        payload: %{message: "Scheduled maintenance in 30 minutes"}
      })
  """
  @spec publish(map(), keyword()) :: {:ok, event_id(), non_neg_integer()} | {:error, term()}
  def publish(event_data, opts \\ []) do
    EventBus.publish(event_data, opts)
  end
  
  @doc """
  Subscribes to events matching the given criteria.
  
  ## Options
  
  - `:channel` - Subscribe to specific channel (`:all` for all channels)
  - `:source` - Filter by source subsystem (`:all` for all sources)
  - `:target` - Filter by target subsystem (`:all` for all targets)
  - `:filter` - Custom filter function `(event) -> boolean()`
  
  ## Examples
  
      # Subscribe to all algedonic alerts
      {:ok, sub_id} = VsmEventBus.subscribe(channel: :algedonic_channel)
      
      # Subscribe to events from System 1
      {:ok, sub_id} = VsmEventBus.subscribe(source: :system1)
      
      # Subscribe with custom filter
      {:ok, sub_id} = VsmEventBus.subscribe(
        channel: :command_channel,
        filter: fn event -> 
          event.type == :scale_operation and event.payload.target_capacity > 100
        end
      )
      
      # Subscribe to everything
      {:ok, sub_id} = VsmEventBus.subscribe()
  """
  @spec subscribe(keyword()) :: {:ok, subscription_id()} | {:error, term()}
  def subscribe(opts \\ []) do
    EventBus.subscribe(opts)
  end
  
  @doc """
  Unsubscribes from events.
  
  ## Examples
  
      {:ok, sub_id} = VsmEventBus.subscribe(channel: :algedonic_channel)
      :ok = VsmEventBus.unsubscribe(sub_id)
  """
  @spec unsubscribe(subscription_id()) :: :ok
  def unsubscribe(subscription_id) do
    EventBus.unsubscribe(subscription_id)
  end
  
  @doc """
  Validates if a route between subsystems is allowed according to VSM principles.
  
  ## Examples
  
      iex> VsmEventBus.validate_route(:system5, :system1, :command_channel)
      {:ok, :direct}
      
      iex> VsmEventBus.validate_route(:system1, :system5, :command_channel)
      {:error, :invalid_vsm_flow}
      
      iex> VsmEventBus.validate_route(:system1, :system5, :algedonic_channel)
      {:ok, :emergency}
  """
  @spec validate_route(subsystem(), subsystem(), channel()) :: {:ok, atom()} | {:error, term()}
  def validate_route(source, target, channel) do
    EventRouter.validate_route(source, target, channel)
  end
  
  @doc """
  Finds the optimal routing path between subsystems.
  
  ## Examples
  
      iex> VsmEventBus.find_route(:system5, :system1, :command_channel)
      {:ok, [:system1]}
      
      iex> VsmEventBus.find_route(:system1, :system5, :algedonic_channel)
      {:ok, [:system5]}
  """
  @spec find_route(subsystem(), subsystem(), channel(), keyword()) :: {:ok, [subsystem()]} | {:error, term()}
  def find_route(source, target, channel, opts \\ []) do
    EventRouter.find_route(source, target, channel, opts)
  end
  
  @doc """
  Retrieves events matching the given criteria.
  
  ## Options
  
  - `:source` - Filter by source subsystem
  - `:target` - Filter by target subsystem
  - `:channel` - Filter by channel type
  - `:type` - Filter by event type
  - `:since` - Get events since timestamp
  - `:limit` - Maximum number of events (default: 1000)
  
  ## Examples
  
      # Get recent algedonic alerts
      events = VsmEventBus.get_events(
        channel: :algedonic_channel,
        since: DateTime.add(DateTime.utc_now(), -3600, :second),
        limit: 50
      )
      
      # Get all events from System 1
      events = VsmEventBus.get_events(source: :system1)
  """
  @spec get_events(keyword()) :: [event()]
  def get_events(criteria \\ []) do
    EventStore.get_events(criteria)
  end
  
  @doc """
  Gets events in a correlation chain.
  
  ## Examples
  
      correlation_id = "conv_123"
      chain = VsmEventBus.get_correlation_chain(correlation_id)
  """
  @spec get_correlation_chain(binary()) :: [event()]
  def get_correlation_chain(correlation_id) do
    EventStore.get_correlation_chain(correlation_id)
  end
  
  @doc """
  Replays events to the calling process.
  
  Events are sent as `{:vsm_event_replay, event}` messages.
  
  ## Examples
  
      # Replay all events from last hour
      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, count} = VsmEventBus.replay_events(self(), since: since)
  """
  @spec replay_events(pid(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def replay_events(target_pid, criteria \\ []) do
    EventStore.replay_events(target_pid, criteria)
  end
  
  @doc """
  Gets comprehensive system statistics.
  
  ## Examples
  
      stats = VsmEventBus.get_stats()
      %{
        event_bus: %{total_events: 1250, active_subscriptions: 8},
        event_store: %{stored_events: 1000, memory_usage: %{...}},
        telemetry: %{events_per_second: 2.5, error_rate: 0.001},
        routing: %{routed: 1240, blocked: 10, cached: 890}
      }
  """
  @spec get_stats() :: map()
  def get_stats do
    %{
      event_bus: EventBus.stats(),
      event_store: EventStore.get_stats(),
      telemetry: EventMetrics.get_performance_summary(),
      routing: EventRouter.get_stats()
    }
  end
  
  @doc """
  Gets current performance metrics.
  
  ## Examples
  
      metrics = VsmEventBus.get_metrics()
      %{
        counters: %{by_channel: %{command_channel: 450}},
        histograms: %{event_processing_duration: %{avg: 1.2, p95: 5.1}},
        uptime_seconds: 3661.2
      }
  """
  @spec get_metrics() :: map()
  def get_metrics do
    EventMetrics.get_metrics()
  end
  
  @doc """
  Lists all active subscriptions.
  
  ## Examples
  
      subs = VsmEventBus.list_subscriptions()
      [
        %{id: "sub_abc123", channel: :algedonic_channel, source: :all, has_filter: true},
        %{id: "sub_def456", channel: :all, source: :system1, has_filter: false}
      ]
  """
  @spec list_subscriptions() :: [map()]
  def list_subscriptions do
    EventBus.list_subscriptions()
  end
  
  ## Convenience Functions
  
  @doc """
  Publishes a command event following VSM hierarchical flow.
  """
  @spec publish_command(subsystem(), subsystem(), event_type(), map(), keyword()) :: 
    {:ok, event_id(), non_neg_integer()} | {:error, term()}
  def publish_command(source, target, type, payload, opts \\ []) do
    event_data = %{
      source: source,
      target: target,
      channel: :command_channel,
      type: type,
      payload: payload
    }
    
    publish(event_data, opts)
  end
  
  @doc """
  Publishes an algedonic alert for emergency situations.
  """
  @spec publish_algedonic_alert(subsystem(), map(), keyword()) :: 
    {:ok, event_id(), non_neg_integer()} | {:error, term()}
  def publish_algedonic_alert(source, payload, opts \\ []) do
    event_data = %{
      source: source,
      target: :system5,
      channel: :algedonic_channel,
      type: :emergency_alert,
      payload: payload
    }
    
    publish(event_data, opts)
  end
  
  @doc """
  Subscribes to algedonic alerts only.
  """
  @spec subscribe_to_alerts(keyword()) :: {:ok, subscription_id()} | {:error, term()}
  def subscribe_to_alerts(opts \\ []) do
    subscribe(Keyword.put(opts, :channel, :algedonic_channel))
  end
  
  @doc """
  Subscribes to events from a specific subsystem.
  """
  @spec subscribe_to_subsystem(subsystem(), keyword()) :: {:ok, subscription_id()} | {:error, term()}
  def subscribe_to_subsystem(subsystem, opts \\ []) do
    subscribe(Keyword.put(opts, :source, subsystem))
  end
end