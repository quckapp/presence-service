import Config

config :presence_service, PresenceService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_presence_service_quckchat_2024",
  watchers: []

config :presence_service, dev_routes: true
config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
