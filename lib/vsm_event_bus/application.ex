defmodule VsmEventBus.Application do
  @moduledoc """
  The VSM Event Bus OTP Application.
  
  This module starts the supervision tree for the VSM Event Bus,
  providing centralized event coordination for Viable System Model implementations.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting VSM Event Bus Application...")
    
    children = [
      # Phoenix PubSub for distributed event handling
      {Phoenix.PubSub, name: VsmEventBus.PubSub},
      
      # Cluster coordination (optional)
      cluster_spec(),
      
      # Core event bus components
      {Registry, keys: :unique, name: VsmEventBus.Registry},
      {DynamicSupervisor, name: VsmEventBus.DynamicSupervisor, strategy: :one_for_one},
      
      # Event bus core
      VsmEventBus.Core.EventBus,
      VsmEventBus.Core.EventRouter,
      VsmEventBus.Core.EventStore,
      
      # VSM channel adapters
      VsmEventBus.Adapters.VSMChannels,
      
      # Monitoring and telemetry
      VsmEventBus.Telemetry.EventMetrics
    ]
    |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: VsmEventBus.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("VSM Event Bus Application started successfully")
        setup_telemetry()
        {:ok, pid}
        
      {:error, reason} ->
        Logger.error("Failed to start VSM Event Bus Application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping VSM Event Bus Application...")
    :ok
  end
  
  # Private functions
  
  defp cluster_spec do
    case Application.get_env(:libcluster, :topologies, []) do
      [] -> nil
      topologies -> {Cluster.Supervisor, [topologies, [name: VsmEventBus.ClusterSupervisor]]}
    end
  end
  
  defp setup_telemetry do
    :telemetry.attach_many(
      "vsm-event-bus-telemetry",
      [
        [:vsm_event_bus, :event, :publish],
        [:vsm_event_bus, :event, :subscribe],
        [:vsm_event_bus, :event, :route],
        [:vsm_event_bus, :event, :filter],
        [:vsm_event_bus, :event, :store]
      ],
      &VsmEventBus.Telemetry.EventMetrics.handle_event/4,
      nil
    )
  end
end