# =============================================================================
# PRODUCTION Environment Configuration
# =============================================================================
# Use this profile for production environment
# Run with: MIX_ENV=production mix phx.server
# =============================================================================

import Config

config :presence_service, PresenceService.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4003")],
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE missing"),
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

# MongoDB - Production (high pool size)
config :presence_service, :mongodb,
  url: System.get_env("MONGODB_URI") || raise("MONGODB_URI missing"),
  pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "50"),
  timeout: 15_000,
  connect_timeout: 10_000

# Redis - Production (database 3 for presence)
config :presence_service, :redis,
  host: System.get_env("REDIS_HOST") || raise("REDIS_HOST missing"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  password: System.get_env("REDIS_PASSWORD"),
  database: String.to_integer(System.get_env("REDIS_DATABASE") || "3"),
  pool_size: 32,
  ssl: System.get_env("REDIS_SSL") == "true"

# Kafka - Production
config :presence_service, :kafka,
  brokers: String.split(System.get_env("KAFKA_BROKERS") || "localhost:9092", ","),
  consumer_group: "presence-service-production",
  ssl: System.get_env("KAFKA_SSL") == "true"

# JWT
config :presence_service, PresenceService.Guardian,
  issuer: "quckapp-auth",
  secret_key: System.get_env("JWT_SECRET") || raise("JWT_SECRET missing")

# libcluster - Production (Kubernetes DNS strategy with optimized settings)
config :libcluster,
  topologies: [
    presence_cluster: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: System.get_env("CLUSTER_SERVICE_NAME") || "presence-service-headless",
        application_name: "presence_service",
        polling_interval: 10_000
      ]
    ]
  ]

# Services
config :presence_service, :services,
  auth_service_url: System.get_env("AUTH_SERVICE_URL") || raise("AUTH_SERVICE_URL missing"),
  user_service_url: System.get_env("USER_SERVICE_URL") || raise("USER_SERVICE_URL missing")

# Logging - Warn level for production
config :logger, level: :warn
