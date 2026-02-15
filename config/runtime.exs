import Config

# =============================================================================
# Runtime Configuration
# =============================================================================
# This file is executed at runtime (not compile time) and is used for
# configuring the application based on environment variables in Docker.
# =============================================================================

if config_env() == :prod do
  # ---------------------------------------------------------------------------
  # Application Secrets
  # ---------------------------------------------------------------------------
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      Environment variable SECRET_KEY_BASE is missing.
      You can generate one by running: mix phx.gen.secret
      """

  # ---------------------------------------------------------------------------
  # Phoenix Endpoint Configuration
  # ---------------------------------------------------------------------------
  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :presence_service, PresenceService.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  # ---------------------------------------------------------------------------
  # MongoDB Configuration
  # ---------------------------------------------------------------------------
  # Supports both MONGODB_URL and MONGODB_URI environment variables
  mongodb_url =
    System.get_env("MONGODB_URL") ||
      System.get_env("MONGODB_URI") ||
      raise """
      Environment variable MONGODB_URL or MONGODB_URI is missing.
      Example: mongodb://localhost:27017/quckapp_presence
      """

  mongodb_pool_size = String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")

  config :presence_service, :mongodb,
    url: mongodb_url,
    pool_size: mongodb_pool_size

  # ---------------------------------------------------------------------------
  # Redis Configuration
  # ---------------------------------------------------------------------------
  # Supports both URL format and individual host/port configuration
  redis_url = System.get_env("REDIS_URL")

  if redis_url do
    # Parse Redis URL (redis://host:port/db)
    uri = URI.parse(redis_url)
    redis_host = uri.host || "localhost"
    redis_port = uri.port || 6379
    redis_database = case uri.path do
      "/" <> db -> String.to_integer(db)
      _ -> 3
    end
    redis_password = if uri.userinfo, do: String.split(uri.userinfo, ":") |> List.last()

    config :presence_service, :redis,
      host: redis_host,
      port: redis_port,
      password: redis_password,
      database: redis_database
  else
    config :presence_service, :redis,
      host: System.get_env("REDIS_HOST") || "localhost",
      port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
      password: System.get_env("REDIS_PASSWORD"),
      database: String.to_integer(System.get_env("REDIS_DATABASE") || "3")
  end

  # ---------------------------------------------------------------------------
  # Kafka Configuration
  # ---------------------------------------------------------------------------
  kafka_brokers_string = System.get_env("KAFKA_BROKERS") || "localhost:9092"

  kafka_brokers =
    kafka_brokers_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn broker ->
      case String.split(broker, ":") do
        [host, port] -> {String.to_charlist(host), String.to_integer(port)}
        [host] -> {String.to_charlist(host), 9092}
      end
    end)

  kafka_enabled = System.get_env("KAFKA_ENABLED", "false") == "true"

  config :presence_service, :kafka,
    enabled: kafka_enabled,
    brokers: kafka_brokers,
    consumer_group: System.get_env("KAFKA_CONSUMER_GROUP") || "presence-service-group"

  # ---------------------------------------------------------------------------
  # JWT / Guardian Configuration
  # ---------------------------------------------------------------------------
  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      Environment variable JWT_SECRET is missing.
      This is required for JWT token verification.
      """

  config :presence_service, PresenceService.Guardian,
    issuer: System.get_env("JWT_ISSUER") || "quckapp",
    secret_key: jwt_secret

  # ---------------------------------------------------------------------------
  # Auth Service Configuration
  # ---------------------------------------------------------------------------
  if auth_service_url = System.get_env("AUTH_SERVICE_URL") do
    config :presence_service, :auth_service,
      url: auth_service_url,
      timeout: String.to_integer(System.get_env("AUTH_SERVICE_TIMEOUT") || "5000")
  end

  # ---------------------------------------------------------------------------
  # Erlang Cluster Configuration
  # ---------------------------------------------------------------------------
  cluster_strategy = System.get_env("CLUSTER_STRATEGY") || "gossip"

  cluster_config =
    case cluster_strategy do
      "dns" ->
        dns_query = System.get_env("CLUSTER_DNS_QUERY") || "presence-service.local"
        [
          presence_cluster: [
            strategy: Cluster.Strategy.DNSPoll,
            config: [
              polling_interval: 5_000,
              query: dns_query,
              node_basename: "presence_service"
            ]
          ]
        ]

      "kubernetes" ->
        k8s_selector = System.get_env("K8S_SELECTOR") || "app=presence-service"
        k8s_namespace = System.get_env("K8S_NAMESPACE") || "default"
        [
          presence_cluster: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              mode: :dns,
              kubernetes_selector: k8s_selector,
              kubernetes_node_basename: "presence_service",
              kubernetes_namespace: k8s_namespace,
              polling_interval: 10_000
            ]
          ]
        ]

      _ ->
        # Default to Gossip strategy
        [presence_cluster: [strategy: Cluster.Strategy.Gossip]]
    end

  config :libcluster, topologies: cluster_config

  # ---------------------------------------------------------------------------
  # Logger Configuration
  # ---------------------------------------------------------------------------
  log_level =
    case System.get_env("LOG_LEVEL", "info") do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level

  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :user_id, :trace_id]
end
