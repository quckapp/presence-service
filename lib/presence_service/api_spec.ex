defmodule PresenceService.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Presence Service API.
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}
  alias PresenceService.{Endpoint, Router}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Presence Service API",
        description: "User presence and online status management API",
        version: "1.0.0"
      },
      servers: [
        %Server{url: get_server_url(), description: "Presence Service"}
      ],
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT Authorization header using the Bearer scheme"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp get_server_url do
    case Application.get_env(:presence_service, Endpoint) do
      nil -> "http://localhost:4000"
      config ->
        host = Keyword.get(config, :url, []) |> Keyword.get(:host, "localhost")
        port = Keyword.get(config, :http, []) |> Keyword.get(:port, 4000)
        scheme = if port == 443, do: "https", else: "http"
        "#{scheme}://#{host}:#{port}"
    end
  end
end
