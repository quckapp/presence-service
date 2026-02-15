# =============================================================================
# LOCAL (Mock) Environment Configuration
# =============================================================================
# Use this profile for local development with Docker containers
# Run with: MIX_ENV=local mix phx.server
# =============================================================================

import Config

config :presence_service, PresenceService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4003],
  check_origin: false,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "local_dev_secret_key_base_presence_service_quckapp_32_chars"

# MongoDB - Local Docker
config :presence_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_presence_local",
  pool_size: 5

# Redis - Local Docker (database 3 for presence)
config :presence_service, :redis,
  host: "localhost",
  port: 6379,
  password: nil,
  database: 3

# Kafka - Local Docker
config :presence_service, :kafka,
  brokers: [{"localhost", 9092}],
  consumer_group: "presence-service-local"

# JWT - Same secret as auth-service local
config :presence_service, PresenceService.Guardian,
  issuer: "quckapp-auth-local",
  secret_key: "bG9jYWwtZGV2LXNlY3JldC1rZXktZm9yLXRlc3Rpbmctb25seS0zMi1jaGFycw=="

# libcluster - Local (Gossip for local development)
config :libcluster,
  topologies: [
    presence_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        multicast_ttl: 1
      ]
    ]
  ]

# Services
config :presence_service, :services,
  auth_service_url: "http://localhost:8081",
  user_service_url: "http://localhost:8082"

# Logging - Verbose for local
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug
