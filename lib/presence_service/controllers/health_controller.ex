defmodule PresenceService.HealthController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs

  alias PresenceService.Schemas.Common

  tags ["Health"]

  operation :index,
    summary: "Health check",
    description: "Basic health check endpoint that returns service status information",
    responses: [
      ok: {"Service is healthy", "application/json", Common.HealthResponse}
    ]

  def index(conn, _params) do
    json(conn, %{status: "healthy", service: "presence-service", version: "1.0.0"})
  end

  operation :ready,
    summary: "Readiness check",
    description: "Checks if the service is ready to handle requests by verifying all dependencies (MongoDB, Redis) are accessible",
    responses: [
      ok: {"Service is ready", "application/json", Common.ReadinessResponse},
      service_unavailable: {"Service is not ready - one or more dependencies are unavailable", "application/json", Common.ReadinessResponse}
    ]

  def ready(conn, _params) do
    checks = %{
      mongo: check_mongo(),
      redis: check_redis()
    }

    all_healthy = Enum.all?(checks, fn {_, status} -> status == :ok end)

    status_code = if all_healthy, do: 200, else: 503
    conn |> put_status(status_code) |> json(%{ready: all_healthy, checks: checks})
  end

  operation :live,
    summary: "Liveness check",
    description: "Simple liveness probe to check if the service process is running",
    responses: [
      ok: {"Service is alive", "application/json", Common.LivenessResponse}
    ]

  def live(conn, _params) do
    json(conn, %{alive: true, timestamp: DateTime.utc_now()})
  end

  defp check_mongo do
    case Mongo.command(:presence_mongo, %{ping: 1}) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_redis do
    case Redix.command(:presence_redis, ["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
