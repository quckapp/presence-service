defmodule PresenceService.Endpoint do
  use Phoenix.Endpoint, otp_app: :presence_service

  @session_options [
    store: :cookie,
    key: "_presence_service_key",
    signing_salt: "presence_salt",
    same_site: "Lax"
  ]

  socket "/socket", PresenceService.UserSocket,
    websocket: [timeout: 45_000],
    longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CORSPlug, origin: ["*"]
  plug PresenceService.Router
end
