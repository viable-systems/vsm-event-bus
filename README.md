# vsm-event-bus

Elixir event bus implementing Stafford Beer's VSM communication channels. Routes events between VSM subsystems (System 1-5) with channel-level validation, persistence, and telemetry. Built on Phoenix PubSub with optional libcluster support for distribution.

## Status

Version 0.1.0. Not published to Hex. The core modules (EventBus, EventRouter, EventStore, VSMChannels, EventMetrics) are implemented with typed specs and documented public API.

## VSM channels

The bus enforces VSM communication rules per Beer's model:

| Channel | Direction | Purpose |
|---------|-----------|---------|
| `command_channel` | S5 -> S4 -> S3 -> S1 | Hierarchical command flow |
| `coordination_channel` | S2 <-> S1 | Anti-oscillatory coordination |
| `audit_channel` | S3* <-> S1 | Sporadic audit |
| `algedonic_channel` | S1 -> S5 | Emergency bypass (pain/pleasure) |
| `resource_bargain_channel` | S1 <-> S3 | Resource negotiation |

Route validation rejects messages that violate these flow patterns (e.g., S1 cannot send on `command_channel` to S5, but can send on `algedonic_channel`).

## Repository structure

| Path | Contents |
|------|----------|
| `lib/vsm_event_bus.ex` | Public API (publish, subscribe, unsubscribe, get_events, replay, stats) |
| `lib/vsm_event_bus/core/event_bus.ex` | GenServer managing subscriptions and dispatch |
| `lib/vsm_event_bus/core/event_router.ex` | VSM route validation and path finding |
| `lib/vsm_event_bus/core/event_store.ex` | In-memory event persistence with query support |
| `lib/vsm_event_bus/adapters/vsm_channels.ex` | Channel definitions and flow rules |
| `lib/vsm_event_bus/telemetry/event_metrics.ex` | Counters, histograms, uptime tracking |
| `lib/vsm_event_bus/application.ex` | OTP application supervisor |
| `test/` | 1 test file |

## Module count

7 `.ex` files under `lib/`. 1 test file.

## Dependencies

| Category | Packages |
|----------|----------|
| PubSub | phoenix_pubsub |
| Clustering | libcluster |
| Telemetry | telemetry, telemetry_metrics |
| Serialization | jason, uuid |
| Dev/test | ex_doc, credo, dialyxir, excoveralls, stream_data |

Requires Elixir >= 1.17.

## Quick start

```bash
git clone https://github.com/viable-systems/vsm-event-bus.git
cd vsm-event-bus
mix deps.get
mix test
```

```elixir
# Publish a command
{:ok, event_id, delivered} = VsmEventBus.publish(%{
  source: :system3,
  target: :system1,
  channel: :command_channel,
  type: :scale_operation,
  payload: %{target_capacity: 150}
})

# Subscribe to algedonic alerts
{:ok, sub_id} = VsmEventBus.subscribe(channel: :algedonic_channel)

# Receive
receive do
  {:vsm_event, event} -> IO.inspect(event)
end

# Query stored events
events = VsmEventBus.get_events(
  channel: :algedonic_channel,
  since: DateTime.add(DateTime.utc_now(), -3600, :second),
  limit: 50
)
```

## Configuration

```elixir
config :vsm_event_bus,
  max_events_history: 10_000,
  enable_persistence: true,
  enable_clustering: true

config :vsm_event_bus, VsmEventBus.PubSub,
  name: VsmEventBus.PubSub,
  adapter: Phoenix.PubSub.PG2

config :libcluster,
  topologies: [
    vsm_cluster: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:node1@host1, :node2@host2]]
    ]
  ]
```

## Known limitations

- Event store is in-memory only; restarts lose all history.
- Only 1 test file; no integration or property-based tests ship despite mentions in the README's testing section.
- Not published to Hex; the hex.pm badge in the old README pointed to a nonexistent package.
- Clustering support via libcluster is declared as a dependency but not tested in the repo.
- No rate limiting on event publishing.

## Related packages

- [vsm-mcp](https://github.com/viable-systems/vsm-mcp) -- top-level VSM orchestrator
- [vsm-pattern-engine](https://github.com/viable-systems/vsm-pattern-engine) -- pattern recognition
- [vsm-vector-store](https://github.com/viable-systems/vsm-vector-store) -- vector database
- [vsm-external-interfaces](https://github.com/viable-systems/vsm-external-interfaces) -- HTTP/WS/gRPC adapters

## License

MIT
