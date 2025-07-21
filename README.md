# VSM Event Bus

[![Hex.pm](https://img.shields.io/hexpm/v/vsm_event_bus.svg)](https://hex.pm/packages/vsm_event_bus)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/vsm_event_bus/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Centralized event coordination for Viable System Model (VSM) implementations in Elixir.

## Overview

The VSM Event Bus provides a scalable, distributed event coordination system specifically designed for Viable System Model architectures. It implements VSM-aware routing, filtering, and persistence while supporting distributed coordination via Phoenix PubSub and libcluster.

## Features

- **🏗️ VSM-Aware Routing**: Understands VSM subsystem communication patterns according to Beer's model
- **⚡ Phoenix PubSub Integration**: Scalable, distributed event handling with automatic failover
- **💾 Event Persistence**: Store and replay events for audit, debugging, and recovery
- **📊 Real-time Monitoring**: Comprehensive telemetry and performance metrics with :telemetry
- **🔗 Clustering Support**: Automatic node discovery and distributed coordination via libcluster
- **🎯 Intelligent Filtering**: Subscribe to events with custom filters and VSM-aware routing validation
- **🔄 Event Replay**: Replay historical events for testing, debugging, and system recovery

## VSM Channel Support

The event bus supports all standard VSM communication channels defined by Stafford Beer:

| Channel | Description | Flow Pattern |
|---------|-------------|--------------|
| `:command_channel` | Hierarchical command flow | S5 → S4 → S3 → S1 |
| `:coordination_channel` | Anti-oscillatory coordination | S2 ↔ S1 |
| `:audit_channel` | Audit communications | S3* ↔ S1 |
| `:algedonic_channel` | Emergency alerts (pain/pleasure) | S1 → S5 |
| `:resource_bargain_channel` | Resource negotiations | S1 ↔ S3 |

## Installation

Add `vsm_event_bus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vsm_event_bus, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Publishing Events

```elixir
# Simple command event
{:ok, event_id, delivered} = VsmEventBus.publish(%{
  source: :system3,
  target: :system1,
  channel: :command_channel,
  type: :scale_operation,
  payload: %{target_capacity: 150}
})

# Algedonic alert (emergency)
{:ok, event_id, delivered} = VsmEventBus.publish_algedonic_alert(:system1, %{
  severity: :critical,
  signal: :pain,
  description: "Database connection pool exhausted",
  metrics: %{current: 100, max: 100, waiting: 250}
})

# Broadcast announcement
{:ok, event_id, delivered} = VsmEventBus.publish(%{
  source: :system4,
  target: :broadcast,
  channel: :command_channel,
  type: :system_announcement,
  payload: %{message: "Scheduled maintenance in 30 minutes"}
})
```

### Subscribing to Events

```elixir
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

# Receiving events
receive do
  {:vsm_event, event} -> 
    IO.puts "Received event: #{event.type} from #{event.source}"
    handle_event(event)
end
```

### Querying Events

```elixir
# Get recent algedonic alerts
events = VsmEventBus.get_events(
  channel: :algedonic_channel,
  since: DateTime.add(DateTime.utc_now(), -3600, :second),
  limit: 50
)

# Get correlation chain
correlation_id = "conv_123"
chain = VsmEventBus.get_correlation_chain(correlation_id)

# Replay events for testing
{:ok, count} = VsmEventBus.replay_events(self(), 
  source: :system1, 
  since: DateTime.add(DateTime.utc_now(), -1800, :second)
)
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs
config :vsm_event_bus,
  max_events_history: 10_000,
  enable_persistence: true,
  enable_clustering: true

# Phoenix PubSub configuration
config :vsm_event_bus, VsmEventBus.PubSub,
  name: VsmEventBus.PubSub,
  adapter: Phoenix.PubSub.PG2
```

### Clustering Configuration

```elixir
# config/config.exs
config :libcluster,
  topologies: [
    vsm_cluster: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:node1@host1, :node2@host2, :node3@host3]]
    ]
  ]
```

### Custom Routing Rules

```elixir
# config/config.exs
config :vsm_event_bus, :routing_rules,
  custom_channel: %{
    :system1 => [:system2, :system3],
    :system2 => [:system1]
  }
```

## Architecture

### Event Structure

All events follow a consistent structure:

```elixir
%{
  id: "evt_550e8400-e29b-41d4-a716-446655440000",
  source: :system1,
  target: :system3,
  channel: :command_channel,
  type: :scale_operation,
  payload: %{target_capacity: 150, reason: "increased_load"},
  timestamp: ~U[2025-01-21 01:00:00Z],
  metadata: %{priority: :high, user_id: "admin"},
  correlation_id: "conv_abc123"
}
```

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    VSM Event Bus                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Event Bus   │  │ Event Router│  │ Event Store         │  │
│  │ (GenServer) │  │ (VSM-aware) │  │ (Persistence)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ VSM Adapter │  │ Telemetry   │  │ Phoenix PubSub      │  │
│  │ (Channels)  │  │ (Metrics)   │  │ (Distribution)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Performance

The VSM Event Bus is designed for high performance:

- **Event Throughput**: 10,000+ events/second on modern hardware
- **Memory Usage**: Configurable event history with automatic cleanup
- **Latency**: Sub-millisecond event routing for local subscribers
- **Clustering**: Automatic failover with Phoenix PubSub's battle-tested distribution

## Monitoring

### Telemetry Events

The event bus emits telemetry events for monitoring:

```elixir
[:vsm_event_bus, :event, :publish]    # Event publication
[:vsm_event_bus, :event, :subscribe]  # New subscriptions
[:vsm_event_bus, :event, :route]      # Event routing
[:vsm_event_bus, :event, :filter]     # Event filtering
[:vsm_event_bus, :event, :store]      # Event storage
```

### Performance Metrics

```elixir
# Get comprehensive statistics
stats = VsmEventBus.get_stats()
%{
  event_bus: %{total_events: 1250, active_subscriptions: 8},
  event_store: %{stored_events: 1000, memory_usage: %{...}},
  telemetry: %{events_per_second: 2.5, error_rate: 0.001},
  routing: %{routed: 1240, blocked: 10, cached: 890}
}

# Get detailed metrics
metrics = VsmEventBus.get_metrics()
%{
  counters: %{by_channel: %{command_channel: 450}},
  histograms: %{event_processing_duration: %{avg: 1.2, p95: 5.1}},
  uptime_seconds: 3661.2
}
```

## Testing

```bash
# Run tests
mix test

# Run tests with coverage
mix test --cover

# Run credo for code quality
mix credo

# Run dialyzer for type checking
mix dialyzer
```

## Integration Examples

### With Phoenix LiveView

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    {:ok, sub_id} = VsmEventBus.subscribe_to_alerts()
    
    socket = assign(socket, :subscription_id, sub_id)
    {:ok, socket}
  end
  
  def handle_info({:vsm_event, event}, socket) do
    # Update LiveView with real-time VSM events
    socket = update(socket, :alerts, fn alerts -> [event | alerts] end)
    {:noreply, socket}
  end
end
```

### With GenServer

```elixir
defmodule MyApp.VSMMonitor do
  use GenServer
  
  def init(_opts) do
    {:ok, sub_id} = VsmEventBus.subscribe(
      channel: :algedonic_channel,
      filter: fn event -> event.payload.severity in [:critical, :high] end
    )
    
    {:ok, %{subscription_id: sub_id, alerts: []}}
  end
  
  def handle_info({:vsm_event, event}, state) do
    # Process VSM events
    case event.channel do
      :algedonic_channel -> handle_algedonic_alert(event)
      :command_channel -> handle_command(event)
      _ -> :ok
    end
    
    {:noreply, state}
  end
end
```

## VSM Integration

The event bus integrates seamlessly with other VSM packages:

```elixir
# With VSM Core
VSMCore.Shared.Message.send(:system1, :system3, :command_channel, :scale, %{})
# Automatically bridged to event bus

# With VSM Telemetry
VsmTelemetry.track_event(event)  # Events flow through event bus

# With VSM Rate Limiter
VsmRateLimiter.check_rate(event)  # Rate limiting based on event patterns
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`mix test`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- **Documentation**: [HexDocs](https://hexdocs.pm/vsm_event_bus/)
- **Source Code**: [GitHub](https://github.com/viable-systems/vsm-event-bus)
- **VSM Project**: [Viable Systems](https://github.com/viable-systems)
- **VSM Docs**: [Documentation](https://viable-systems.github.io/vsm-docs/)

## Viable System Model

Learn more about the Viable System Model:

- [Brain of the Firm](https://en.wikipedia.org/wiki/The_Brain_of_the_Firm) by Stafford Beer
- [VSM Guide](https://www.esrad.org.uk/resources/vsmg_3/screen.php?page=home) - Comprehensive VSM Guide
- [Complexity and Management](https://books.google.com/books/about/Complexity_and_Management.html) - Modern applications of VSM