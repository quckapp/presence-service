import Config

config :presence_service, PresenceService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_presence_service_quckapp_2024",
  watchers: []

# MongoDB configuration for development
config :presence_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_presence_dev",
  pool_size: 5

# Redis configuration for development
config :presence_service, :redis,
  host: "localhost",
  port: 6379,
  database: 3

# Kafka configuration for development (disabled by default)
config :presence_service, :kafka,
  enabled: false,
  brokers: [{~c"localhost", 9092}],
  consumer_group: "presence-service-group-dev"

# Guardian JWT configuration for development
config :presence_service, PresenceService.Guardian,
  issuer: "presence_service",
  secret_key: "dev_jwt_secret_for_presence_service"

# libcluster topology for development (no clustering)
config :libcluster, topologies: []

config :presence_service, dev_routes: true
config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
