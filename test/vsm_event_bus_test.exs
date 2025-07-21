defmodule VsmEventBusTest do
  use ExUnit.Case
  doctest VsmEventBus

  alias VsmEventBus.Core.{EventBus, EventRouter, EventStore}

  setup do
    # Ensure clean state for each test
    # GenServer.call(EventBus, :clear_events)
    :ok
  end

  describe "event publishing" do
    test "publishes basic VSM event successfully" do
      event_data = %{
        source: :system3,
        target: :system1,
        channel: :command_channel,
        type: :scale_operation,
        payload: %{target_capacity: 150}
      }

      assert {:ok, event_id, delivered_count} = VsmEventBus.publish(event_data)
      assert is_binary(event_id)
      assert delivered_count >= 0
    end

    test "publishes algedonic alert" do
      payload = %{
        severity: :critical,
        signal: :pain,
        description: "Database connection pool exhausted"
      }

      assert {:ok, event_id, delivered_count} = VsmEventBus.publish_algedonic_alert(:system1, payload)
      assert is_binary(event_id)
    end

    test "publishes command event" do
      assert {:ok, event_id, delivered_count} = VsmEventBus.publish_command(
        :system3, :system1, :scale_operation, %{target_capacity: 100}
      )
      assert is_binary(event_id)
    end
  end

  describe "event subscription" do
    test "subscribes to events successfully" do
      assert {:ok, subscription_id} = VsmEventBus.subscribe()
      assert is_binary(subscription_id)
    end

    test "subscribes to specific channel" do
      assert {:ok, subscription_id} = VsmEventBus.subscribe(channel: :algedonic_channel)
      assert is_binary(subscription_id)
    end

    test "subscribes with filter" do
      filter = fn event -> event.payload.severity == :critical end
      assert {:ok, subscription_id} = VsmEventBus.subscribe(filter: filter)
      assert is_binary(subscription_id)
    end

    test "unsubscribes successfully" do
      {:ok, subscription_id} = VsmEventBus.subscribe()
      assert :ok = VsmEventBus.unsubscribe(subscription_id)
    end
  end

  describe "event routing validation" do
    test "validates correct VSM command flow" do
      assert {:ok, :direct} = VsmEventBus.validate_route(:system5, :system1, :command_channel)
      assert {:ok, :direct} = VsmEventBus.validate_route(:system3, :system1, :command_channel)
    end

    test "rejects invalid VSM command flow" do
      assert {:error, :invalid_vsm_flow} = VsmEventBus.validate_route(:system1, :system5, :command_channel)
    end

    test "validates algedonic emergency route" do
      assert {:ok, :direct} = VsmEventBus.validate_route(:system1, :system5, :algedonic_channel)
    end

    test "validates coordination channel" do
      assert {:ok, :direct} = VsmEventBus.validate_route(:system2, :system1, :coordination_channel)
      assert {:ok, :direct} = VsmEventBus.validate_route(:system1, :system2, :coordination_channel)
    end
  end

  describe "event retrieval" do
    test "gets events with criteria" do
      # Publish some test events
      VsmEventBus.publish(%{
        source: :system1, target: :system3, channel: :command_channel,
        type: :test_event, payload: %{test: true}
      })

      events = VsmEventBus.get_events(source: :system1)
      assert length(events) >= 1
      assert Enum.all?(events, & &1.source == :system1)
    end

    test "gets correlation chain" do
      correlation_id = "test_correlation_#{:rand.uniform(1000)}"
      
      VsmEventBus.publish(%{
        source: :system1, target: :system3, channel: :command_channel,
        type: :start_chain, payload: %{}, correlation_id: correlation_id
      })

      chain = VsmEventBus.get_correlation_chain(correlation_id)
      assert length(chain) >= 1
      assert Enum.all?(chain, & &1.correlation_id == correlation_id)
    end
  end

  describe "system statistics" do
    test "gets comprehensive stats" do
      stats = VsmEventBus.get_stats()
      
      assert Map.has_key?(stats, :event_bus)
      assert Map.has_key?(stats, :event_store)
      assert Map.has_key?(stats, :telemetry)
      assert Map.has_key?(stats, :routing)
    end

    test "gets performance metrics" do
      metrics = VsmEventBus.get_metrics()
      
      assert Map.has_key?(metrics, :counters)
      assert Map.has_key?(metrics, :histograms)
      assert Map.has_key?(metrics, :uptime_seconds)
    end

    test "lists subscriptions" do
      {:ok, _sub_id} = VsmEventBus.subscribe(channel: :algedonic_channel)
      
      subscriptions = VsmEventBus.list_subscriptions()
      assert is_list(subscriptions)
      assert length(subscriptions) >= 1
    end
  end

  describe "convenience functions" do
    test "subscribes to alerts" do
      assert {:ok, subscription_id} = VsmEventBus.subscribe_to_alerts()
      assert is_binary(subscription_id)
    end

    test "subscribes to subsystem" do
      assert {:ok, subscription_id} = VsmEventBus.subscribe_to_subsystem(:system1)
      assert is_binary(subscription_id)
    end
  end

  describe "event flow integration" do
    test "end-to-end event flow" do
      test_pid = self()
      
      # Subscribe to events
      {:ok, _sub_id} = VsmEventBus.subscribe(
        channel: :command_channel,
        filter: fn event -> event.type == :integration_test end
      )

      # Publish event
      {:ok, event_id, _delivered} = VsmEventBus.publish(%{
        source: :system3,
        target: :system1,
        channel: :command_channel,
        type: :integration_test,
        payload: %{test_data: "hello world"}
      })

      # Verify event received
      assert_receive {:vsm_event, event}, 1000
      assert event.id == event_id
      assert event.type == :integration_test
      assert event.payload.test_data == "hello world"
    end
  end
end