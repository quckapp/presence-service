import Config

if config_env() == :prod do
  secret_key_base = System.get_env("SECRET_KEY_BASE") || raise "SECRET_KEY_BASE is missing"
  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4001")

  config :presence_service, PresenceService.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :presence_service, :mongodb,
    url: System.get_env("MONGODB_URI") || raise("MONGODB_URI is missing"),
    pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")

  config :presence_service, :redis,
    host: System.get_env("REDIS_HOST") || "localhost",
    port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
    password: System.get_env("REDIS_PASSWORD")

  config :presence_service, :kafka,
    brokers: String.split(System.get_env("KAFKA_BROKERS") || "localhost:9092", ",")

  config :presence_service, PresenceService.Guardian,
    secret_key: System.get_env("JWT_SECRET")
end
