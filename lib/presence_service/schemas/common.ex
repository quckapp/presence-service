defmodule PresenceService.Schemas.Common do
  @moduledoc """
  Common schemas used across the Presence Service API.
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule SuccessResponse do
    @moduledoc "Generic success response wrapper"
    OpenApiSpex.schema(%{
      title: "SuccessResponse",
      description: "Generic success response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        message: %Schema{type: :string, description: "Optional success message"}
      },
      required: [:success],
      example: %{
        "success" => true,
        "message" => "Operation completed successfully"
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc "Generic error response wrapper"
    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Generic error response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Always false for errors"},
        error: %Schema{type: :string, description: "Error message describing what went wrong"}
      },
      required: [:success, :error],
      example: %{
        "success" => false,
        "error" => "Resource not found"
      }
    })
  end

  defmodule HealthResponse do
    @moduledoc "Health check response"
    OpenApiSpex.schema(%{
      title: "HealthResponse",
      description: "Health check response",
      type: :object,
      properties: %{
        status: %Schema{type: :string, description: "Health status"},
        service: %Schema{type: :string, description: "Service name"},
        version: %Schema{type: :string, description: "Service version"}
      },
      required: [:status, :service, :version],
      example: %{
        "status" => "healthy",
        "service" => "presence-service",
        "version" => "1.0.0"
      }
    })
  end

  defmodule ReadinessResponse do
    @moduledoc "Readiness check response"
    OpenApiSpex.schema(%{
      title: "ReadinessResponse",
      description: "Readiness check response with dependency status",
      type: :object,
      properties: %{
        ready: %Schema{type: :boolean, description: "Overall readiness status"},
        checks: %Schema{
          type: :object,
          description: "Individual dependency check results",
          properties: %{
            mongo: %Schema{type: :string, enum: ["ok", "error"], description: "MongoDB connection status"},
            redis: %Schema{type: :string, enum: ["ok", "error"], description: "Redis connection status"}
          }
        }
      },
      required: [:ready, :checks],
      example: %{
        "ready" => true,
        "checks" => %{
          "mongo" => "ok",
          "redis" => "ok"
        }
      }
    })
  end

  defmodule LivenessResponse do
    @moduledoc "Liveness check response"
    OpenApiSpex.schema(%{
      title: "LivenessResponse",
      description: "Liveness check response",
      type: :object,
      properties: %{
        alive: %Schema{type: :boolean, description: "Whether the service is alive"},
        timestamp: %Schema{type: :string, format: :"date-time", description: "Current server timestamp"}
      },
      required: [:alive, :timestamp],
      example: %{
        "alive" => true,
        "timestamp" => "2024-01-15T10:30:00Z"
      }
    })
  end
end
