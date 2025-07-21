defmodule VsmEventBus.Telemetry.EventMetrics do
  @moduledoc """
  Telemetry and metrics collection for VSM Event Bus.
  
  This module provides comprehensive monitoring and metrics for event bus
  operations, including performance tracking and health monitoring.
  """
  
  use GenServer
  require Logger
  
  @metrics_retention_seconds 3600  # 1 hour
  @cleanup_interval 300_000  # 5 minutes
  
  defstruct [
    metrics: %{},
    counters: %{},
    histograms: %{},
    last_cleanup: nil
  ]
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Handles telemetry events from the event bus.
  """
  def handle_event(event_name, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
  end
  
  @doc """
  Gets current metrics snapshot.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Gets performance summary.
  """
  def get_performance_summary do
    GenServer.call(__MODULE__, :get_performance_summary)
  end
  
  @doc """
  Resets all metrics.
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end
  
  ## Server Implementation
  
  @impl true
  def init(_opts) do
    Logger.info("VSM Event Bus Telemetry started")
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    state = %__MODULE__{
      metrics: init_metrics(),
      counters: init_counters(),
      histograms: init_histograms(),
      last_cleanup: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:telemetry_event, event_name, measurements, metadata}, state) do
    new_state = process_telemetry_event(event_name, measurements, metadata, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      counters: state.counters,
      histograms: compute_histogram_stats(state.histograms),
      metrics: state.metrics,
      last_updated: DateTime.utc_now(),
      uptime_seconds: uptime_seconds()
    }
    
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:get_performance_summary, _from, state) do
    summary = build_performance_summary(state)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_call(:reset_metrics, _from, state) do
    Logger.info("Resetting VSM Event Bus metrics")
    
    new_state = %{state |
      metrics: init_metrics(),
      counters: init_counters(),
      histograms: init_histograms()
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_metrics(state)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp init_metrics do
    %{
      events_published_total: 0,
      events_subscribed_total: 0,
      events_routed_total: 0,
      events_filtered_total: 0,
      events_stored_total: 0,
      routing_errors_total: 0,
      subscription_errors_total: 0
    }
  end
  
  defp init_counters do
    %{
      by_channel: %{},
      by_source: %{},
      by_target: %{},
      by_type: %{},
      by_hour: %{}
    }
  end
  
  defp init_histograms do
    %{
      event_processing_duration: [],
      event_routing_duration: [],
      event_size_bytes: [],
      subscription_count: []
    }
  end
  
  defp process_telemetry_event([:vsm_event_bus, :event, :publish], measurements, metadata, state) do
    timestamp = DateTime.utc_now()
    hour_key = DateTime.to_date(timestamp)
    
    # Update counters
    new_counters = state.counters
    |> update_counter([:by_channel, metadata.channel], measurements.count)
    |> update_counter([:by_source, metadata.source], measurements.count)
    |> update_counter([:by_hour, hour_key], measurements.count)
    
    # Update metrics
    new_metrics = Map.update!(state.metrics, :events_published_total, &(&1 + measurements.count))
    
    # Update histograms if duration provided
    new_histograms = case Map.get(measurements, :duration_microseconds) do
      nil -> state.histograms
      duration -> update_histogram(state.histograms, :event_processing_duration, duration)
    end
    
    %{state | counters: new_counters, metrics: new_metrics, histograms: new_histograms}
  end
  
  defp process_telemetry_event([:vsm_event_bus, :event, :subscribe], measurements, metadata, state) do
    # Update subscription metrics
    new_counters = update_counter(state.counters, [:by_channel, metadata.channel], measurements.count)
    new_metrics = Map.update!(state.metrics, :events_subscribed_total, &(&1 + measurements.count))
    
    %{state | counters: new_counters, metrics: new_metrics}
  end
  
  defp process_telemetry_event([:vsm_event_bus, :event, :route], measurements, metadata, state) do
    # Update routing metrics
    new_metrics = Map.update!(state.metrics, :events_routed_total, &(&1 + measurements.count))
    
    # Track routing type distribution
    new_counters = update_counter(state.counters, [:by_target, metadata.target_type], measurements.count)
    
    %{state | counters: new_counters, metrics: new_metrics}
  end
  
  defp process_telemetry_event([:vsm_event_bus, :event, :filter], measurements, _metadata, state) do
    new_metrics = Map.update!(state.metrics, :events_filtered_total, &(&1 + measurements.count))
    %{state | metrics: new_metrics}
  end
  
  defp process_telemetry_event([:vsm_event_bus, :event, :store], measurements, metadata, state) do
    # Update storage metrics
    new_metrics = Map.update!(state.metrics, :events_stored_total, &(&1 + measurements.count))
    
    # Track event sizes
    new_histograms = case Map.get(measurements, :size_bytes) do
      nil -> state.histograms
      size -> update_histogram(state.histograms, :event_size_bytes, size)
    end
    
    %{state | metrics: new_metrics, histograms: new_histograms}
  end
  
  defp process_telemetry_event(_event_name, _measurements, _metadata, state) do
    # Unknown event, no-op
    state
  end
  
  defp update_counter(counters, path, increment) do
    update_in(counters, path, fn current -> (current || 0) + increment end)
  end
  
  defp update_histogram(histograms, metric_name, value) when is_number(value) do
    current_values = Map.get(histograms, metric_name, [])
    
    # Keep only recent values (last 1000 for performance)
    new_values = [value | Enum.take(current_values, 999)]
    
    Map.put(histograms, metric_name, new_values)
  end
  
  defp compute_histogram_stats(histograms) do
    histograms
    |> Enum.map(fn {metric_name, values} ->
      {metric_name, compute_stats(values)}
    end)
    |> Map.new()
  end
  
  defp compute_stats([]), do: %{count: 0}
  defp compute_stats(values) do
    sorted = Enum.sort(values)
    count = length(values)
    sum = Enum.sum(values)
    
    %{
      count: count,
      sum: sum,
      avg: sum / count,
      min: List.first(sorted),
      max: List.last(sorted),
      p50: percentile(sorted, 0.5),
      p90: percentile(sorted, 0.9),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99)
    }
  end
  
  defp percentile(sorted_values, p) when p >= 0 and p <= 1 do
    count = length(sorted_values)
    index = round(p * (count - 1))
    Enum.at(sorted_values, index)
  end
  
  defp build_performance_summary(state) do
    histogram_stats = compute_histogram_stats(state.histograms)
    
    %{
      total_events: state.metrics.events_published_total,
      events_per_second: calculate_events_per_second(state),
      error_rate: calculate_error_rate(state),
      avg_processing_time: get_in(histogram_stats, [:event_processing_duration, :avg]),
      avg_event_size: get_in(histogram_stats, [:event_size_bytes, :avg]),
      top_channels: get_top_channels(state.counters),
      top_sources: get_top_sources(state.counters),
      health_status: determine_health_status(state)
    }
  end
  
  defp calculate_events_per_second(state) do
    uptime = uptime_seconds()
    if uptime > 0 do
      state.metrics.events_published_total / uptime
    else
      0.0
    end
  end
  
  defp calculate_error_rate(state) do
    total_events = state.metrics.events_published_total
    total_errors = state.metrics.routing_errors_total + state.metrics.subscription_errors_total
    
    if total_events > 0 do
      total_errors / total_events
    else
      0.0
    end
  end
  
  defp get_top_channels(counters) do
    counters
    |> get_in([:by_channel])
    |> Enum.sort_by(fn {_channel, count} -> count end, :desc)
    |> Enum.take(5)
  end
  
  defp get_top_sources(counters) do
    counters
    |> get_in([:by_source])
    |> Enum.sort_by(fn {_source, count} -> count end, :desc)
    |> Enum.take(5)
  end
  
  defp determine_health_status(state) do
    error_rate = calculate_error_rate(state)
    
    cond do
      error_rate > 0.1 -> :critical
      error_rate > 0.05 -> :warning
      state.metrics.events_published_total == 0 -> :idle
      true -> :healthy
    end
  end
  
  defp cleanup_old_metrics(state) do
    # For now, just update last cleanup time
    # In a production system, this would clean up old histogram data
    %{state | last_cleanup: DateTime.utc_now()}
  end
  
  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms / 1000
  end
end