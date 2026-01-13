defmodule PresenceService.Application do
  @moduledoc """
  Presence Service Application - Manages user online/offline status with MongoDB storage.
  Built for high concurrency using BEAM VM's actor model.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Telemetry Supervisor
      PresenceService.Telemetry,
      # PubSub for distributed messaging
      {Phoenix.PubSub, name: PresenceService.PubSub},
      # MongoDB Connection Pool
      {Mongo, [
        name: :presence_mongo,
        url: Application.get_env(:presence_service, :mongodb)[:url],
        pool_size: Application.get_env(:presence_service, :mongodb)[:pool_size] || 10
      ]},
      # Redis Connection Pool
      {Redix, [
        host: Application.get_env(:presence_service, :redis)[:host],
        port: Application.get_env(:presence_service, :redis)[:port],
        database: Application.get_env(:presence_service, :redis)[:database] || 3,
        name: :presence_redis
      ]},
      # Horde Distributed Registry for presence tracking
      {Horde.Registry, [name: PresenceService.PresenceRegistry, keys: :unique]},
      # Horde Dynamic Supervisor for user sessions
      {Horde.DynamicSupervisor, [name: PresenceService.PresenceSupervisor, strategy: :one_for_one]},
      # Presence Manager GenServer
      PresenceService.PresenceManager,
      # Kafka Consumer for presence events
      PresenceService.Kafka.Consumer,
      # Cluster Manager
      {Cluster.Supervisor, [
        Application.get_env(:libcluster, :topologies),
        [name: PresenceService.ClusterSupervisor]
      ]},
      # Phoenix Endpoint
      PresenceService.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PresenceService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PresenceService.Endpoint.config_change(changed, removed)
    :ok
  end
end
