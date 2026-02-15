# =============================================================================
# STAGING Environment Configuration
# =============================================================================
# Use this profile for staging environment
# Run with: MIX_ENV=staging mix phx.server
# =============================================================================

import Config

config :presence_service, PresenceService.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4003")],
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

# MongoDB - Staging (higher pool size)
config :presence_service, :mongodb,
  url: System.get_env("MONGODB_URI"),
  pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "25")

# Redis - Staging (database 3 for presence)
config :presence_service, :redis,
  host: System.get_env("REDIS_HOST"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  password: System.get_env("REDIS_PASSWORD"),
  database: String.to_integer(System.get_env("REDIS_DATABASE") || "3"),
  pool_size: 16

# Kafka - Staging
config :presence_service, :kafka,
  brokers: [System.get_env("KAFKA_BROKER") || "localhost:9092"],
  consumer_group: "presence-service-staging"

# JWT
config :presence_service, PresenceService.Guardian,
  issuer: "quckapp-auth",
  secret_key: System.get_env("JWT_SECRET")

# libcluster - Staging (Kubernetes DNS strategy)
config :libcluster,
  topologies: [
    presence_cluster: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: System.get_env("CLUSTER_SERVICE_NAME") || "presence-service-headless",
        application_name: "presence_service",
        polling_interval: 5_000
      ]
    ]
  ]

# Services
config :presence_service, :services,
  auth_service_url: System.get_env("AUTH_SERVICE_URL"),
  user_service_url: System.get_env("USER_SERVICE_URL")

# Logging - Info level for staging
config :logger, level: :info
