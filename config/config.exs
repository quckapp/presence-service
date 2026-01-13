import Config

config :presence_service, namespace: PresenceService

config :presence_service, PresenceService.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: PresenceService.ErrorJSON], layout: false],
  pubsub_server: PresenceService.PubSub,
  live_view: [signing_salt: "presence_salt"]

config :presence_service, :mongodb,
  url: System.get_env("MONGODB_URI") || "mongodb://localhost:27017/quckchat_presence",
  pool_size: 10

config :presence_service, :redis,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  database: 3

config :presence_service, :kafka,
  brokers: [System.get_env("KAFKA_BROKER") || "localhost:9092"],
  consumer_group: "presence-service-group"

config :presence_service, PresenceService.Guardian,
  issuer: "quckchat",
  secret_key: System.get_env("JWT_SECRET") || "your-secret-key"

config :libcluster, topologies: [presence_cluster: [strategy: Cluster.Strategy.Gossip]]

config :logger, :console, format: "$time $metadata[$level] $message\n", metadata: [:request_id, :user_id]
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
