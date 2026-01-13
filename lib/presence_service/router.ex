defmodule PresenceService.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
    plug PresenceService.Plugs.AuthPlug
  end

  pipeline :public do
    plug :accepts, ["json"]
  end

  scope "/api/v1/presence", PresenceService do
    pipe_through :api

    get "/:user_id", PresenceController, :show
    post "/", PresenceController, :update
    post "/bulk", PresenceController, :bulk_get
    post "/heartbeat", PresenceController, :heartbeat
    get "/stats/online", PresenceController, :online_count
  end

  scope "/health", PresenceService do
    pipe_through :public
    get "/", HealthController, :index
    get "/ready", HealthController, :ready
    get "/live", HealthController, :live
  end

  if Application.compile_env(:presence_service, :dev_routes) do
    import Phoenix.LiveDashboard.Router
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: PresenceService.Telemetry
    end
  end
end
