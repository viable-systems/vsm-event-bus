defmodule VsmEventBus.Core.EventStore do
  @moduledoc """
  Event persistence and replay functionality for VSM Event Bus.
  
  This module provides event sourcing capabilities, allowing events to be
  stored, retrieved, and replayed for audit, debugging, and recovery purposes.
  """
  
  use GenServer
  require Logger
  
  alias VsmEventBus.Core.EventBus
  
  @max_events_default 10_000
  @cleanup_interval 60_000  # 1 minute
  
  defstruct [
    events: [],
    event_index: %{},
    event_count: 0,
    max_events: @max_events_default,
    storage_backend: :memory,
    last_cleanup: nil
  ]
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Stores an event in the event store.
  """
  def store_event(event) do
    GenServer.cast(__MODULE__, {:store_event, event})
  end
  
  @doc """
  Retrieves an event by ID.
  """
  def get_event(event_id) do
    GenServer.call(__MODULE__, {:get_event, event_id})
  end
  
  @doc """
  Gets events matching the given criteria.
  
  ## Options
  
  - `:source` - Filter by source subsystem
  - `:target` - Filter by target subsystem  
  - `:channel` - Filter by channel type
  - `:type` - Filter by event type
  - `:since` - Get events since timestamp
  - `:limit` - Maximum number of events to return
  """
  def get_events(criteria \\ []) do
    GenServer.call(__MODULE__, {:get_events, criteria})
  end
  
  @doc """
  Gets events in a correlation chain.
  """
  def get_correlation_chain(correlation_id) do
    GenServer.call(__MODULE__, {:get_correlation_chain, correlation_id})
  end
  
  @doc """
  Replays events to a subscriber.
  """
  def replay_events(subscriber_pid, criteria \\ []) do
    GenServer.call(__MODULE__, {:replay_events, subscriber_pid, criteria})
  end
  
  @doc """
  Gets storage statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Clears all stored events (use with caution).
  """
  def clear_events do
    GenServer.call(__MODULE__, :clear_events)
  end
  
  ## Server Implementation
  
  @impl true
  def init(opts) do
    max_events = Keyword.get(opts, :max_events, @max_events_default)
    storage_backend = Keyword.get(opts, :storage_backend, :memory)
    
    Logger.info("VSM Event Store started with #{storage_backend} backend, max #{max_events} events")
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    state = %__MODULE__{
      max_events: max_events,
      storage_backend: storage_backend,
      last_cleanup: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:store_event, event}, state) do
    # Add to events list (newest first)
    new_events = [event | state.events]
    
    # Trim if over limit
    trimmed_events = Enum.take(new_events, state.max_events)
    
    # Update index
    new_index = Map.put(state.event_index, event.id, event)
    
    new_state = %{state |
      events: trimmed_events,
      event_index: new_index,
      event_count: state.event_count + 1
    }
    
    :telemetry.execute(
      [:vsm_event_bus, :event, :store],
      %{count: 1, size_bytes: estimate_event_size(event)},
      %{channel: event.channel, type: event.type}
    )
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:get_event, event_id}, _from, state) do
    event = Map.get(state.event_index, event_id)
    {:reply, event, state}
  end
  
  @impl true
  def handle_call({:get_events, criteria}, _from, state) do
    filtered_events = filter_events(state.events, criteria)
    {:reply, filtered_events, state}
  end
  
  @impl true
  def handle_call({:get_correlation_chain, correlation_id}, _from, state) do
    chain_events = 
      state.events
      |> Enum.filter(fn event -> 
        event.correlation_id == correlation_id or event.id == correlation_id
      end)
      |> Enum.sort_by(& &1.timestamp, DateTime)
    
    {:reply, chain_events, state}
  end
  
  @impl true
  def handle_call({:replay_events, subscriber_pid, criteria}, _from, state) do
    events_to_replay = filter_events(state.events, criteria)
    
    # Send events in chronological order
    events_to_replay
    |> Enum.reverse()
    |> Enum.each(fn event ->
      send(subscriber_pid, {:vsm_event_replay, event})
    end)
    
    {:reply, {:ok, length(events_to_replay)}, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_events: state.event_count,
      stored_events: length(state.events),
      max_events: state.max_events,
      index_size: map_size(state.event_index),
      storage_backend: state.storage_backend,
      last_cleanup: state.last_cleanup,
      memory_usage: estimate_memory_usage(state)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:clear_events, _from, state) do
    Logger.warning("Clearing all events from VSM Event Store")
    
    new_state = %{state |
      events: [],
      event_index: %{}
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    new_state = perform_cleanup(state)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp filter_events(events, criteria) do
    limit = Keyword.get(criteria, :limit, 1000)
    
    events
    |> Enum.filter(&matches_criteria?(&1, criteria))
    |> Enum.take(limit)
  end
  
  defp matches_criteria?(event, criteria) do
    Enum.all?(criteria, fn
      {:source, source} -> event.source == source
      {:target, target} -> event.target == target or (is_list(event.target) and target in event.target)
      {:channel, channel} -> event.channel == channel
      {:type, type} -> event.type == type
      {:since, since_time} -> DateTime.compare(event.timestamp, since_time) != :lt
      {:limit, _} -> true  # Handled separately
      _ -> true
    end)
  end
  
  defp perform_cleanup(state) do
    # Remove duplicate events from index that are no longer in events list
    event_ids = MapSet.new(state.events, & &1.id)
    
    new_index = 
      state.event_index
      |> Enum.filter(fn {id, _event} -> MapSet.member?(event_ids, id) end)
      |> Map.new()
    
    cleanup_count = map_size(state.event_index) - map_size(new_index)
    
    if cleanup_count > 0 do
      Logger.debug("Cleaned up #{cleanup_count} stale event index entries")
    end
    
    %{state |
      event_index: new_index,
      last_cleanup: DateTime.utc_now()
    }
  end
  
  defp estimate_event_size(event) do
    # Rough estimate in bytes
    event
    |> :erlang.term_to_binary()
    |> byte_size()
  end
  
  defp estimate_memory_usage(state) do
    events_size = 
      state.events
      |> Enum.map(&estimate_event_size/1)
      |> Enum.sum()
    
    index_size = 
      state.event_index
      |> :erlang.term_to_binary()
      |> byte_size()
    
    %{
      events_bytes: events_size,
      index_bytes: index_size,
      total_bytes: events_size + index_size
    }
  end
end