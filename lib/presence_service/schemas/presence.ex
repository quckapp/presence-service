defmodule PresenceService.Schemas.Presence do
  @moduledoc """
  Schemas for presence-related API endpoints.
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule DeviceInfo do
    @moduledoc "Device information schema"
    OpenApiSpex.schema(%{
      title: "DeviceInfo",
      description: "Information about the user's device",
      type: :object,
      properties: %{
        device_id: %Schema{type: :string, description: "Unique device identifier"},
        device_type: %Schema{type: :string, description: "Type of device (mobile, desktop, tablet, etc.)"},
        platform: %Schema{type: :string, description: "Operating system or platform"},
        app_version: %Schema{type: :string, description: "Application version"}
      },
      example: %{
        "device_id" => "device-abc-123",
        "device_type" => "mobile",
        "platform" => "iOS",
        "app_version" => "2.1.0"
      }
    })
  end

  defmodule PresenceData do
    @moduledoc "User presence data"
    OpenApiSpex.schema(%{
      title: "PresenceData",
      description: "User presence information",
      type: :object,
      properties: %{
        user_id: %Schema{type: :string, description: "Unique user identifier"},
        status: %Schema{
          type: :string,
          enum: ["online", "offline", "away", "busy", "invisible"],
          description: "Current presence status"
        },
        last_seen: %Schema{type: :string, format: :"date-time", description: "Last activity timestamp"},
        device_info: DeviceInfo
      },
      required: [:user_id, :status],
      example: %{
        "user_id" => "user-123",
        "status" => "online",
        "last_seen" => "2024-01-15T10:30:00Z",
        "device_info" => %{
          "device_id" => "device-abc-123",
          "device_type" => "mobile",
          "platform" => "iOS",
          "app_version" => "2.1.0"
        }
      }
    })
  end

  defmodule PresenceResponse do
    @moduledoc "Response containing user presence data"
    OpenApiSpex.schema(%{
      title: "PresenceResponse",
      description: "Response containing user presence information",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: PresenceData
      },
      required: [:success, :data],
      example: %{
        "success" => true,
        "data" => %{
          "user_id" => "user-123",
          "status" => "online",
          "last_seen" => "2024-01-15T10:30:00Z",
          "device_info" => %{
            "device_id" => "device-abc-123",
            "device_type" => "mobile"
          }
        }
      }
    })
  end

  defmodule UpdatePresenceRequest do
    @moduledoc "Request to update user presence"
    OpenApiSpex.schema(%{
      title: "UpdatePresenceRequest",
      description: "Request body for updating user presence status",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["online", "offline", "away", "busy", "invisible"],
          description: "New presence status to set"
        },
        device_info: DeviceInfo,
        metadata: %Schema{
          type: :object,
          description: "Additional metadata for the presence update",
          additionalProperties: true
        }
      },
      required: [:status],
      example: %{
        "status" => "online",
        "device_info" => %{
          "device_id" => "device-abc-123",
          "device_type" => "mobile",
          "platform" => "iOS"
        },
        "metadata" => %{
          "custom_status" => "Working from home"
        }
      }
    })
  end

  defmodule BulkPresenceRequest do
    @moduledoc "Request for bulk presence lookup"
    OpenApiSpex.schema(%{
      title: "BulkPresenceRequest",
      description: "Request body for retrieving presence of multiple users",
      type: :object,
      properties: %{
        user_ids: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Array of user IDs to get presence for",
          minItems: 1,
          maxItems: 100
        }
      },
      required: [:user_ids],
      example: %{
        "user_ids" => ["user-123", "user-456", "user-789"]
      }
    })
  end

  defmodule BulkPresenceResponse do
    @moduledoc "Response containing multiple user presences"
    OpenApiSpex.schema(%{
      title: "BulkPresenceResponse",
      description: "Response containing presence information for multiple users",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :object,
          description: "Map of user IDs to their presence data",
          additionalProperties: PresenceData
        }
      },
      required: [:success, :data],
      example: %{
        "success" => true,
        "data" => %{
          "user-123" => %{
            "user_id" => "user-123",
            "status" => "online",
            "last_seen" => "2024-01-15T10:30:00Z"
          },
          "user-456" => %{
            "user_id" => "user-456",
            "status" => "away",
            "last_seen" => "2024-01-15T10:25:00Z"
          }
        }
      }
    })
  end

  defmodule HeartbeatRequest do
    @moduledoc "Request to send a heartbeat"
    OpenApiSpex.schema(%{
      title: "HeartbeatRequest",
      description: "Request body for sending a presence heartbeat",
      type: :object,
      properties: %{
        device_id: %Schema{type: :string, description: "Device identifier sending the heartbeat"}
      },
      example: %{
        "device_id" => "device-abc-123"
      }
    })
  end

  defmodule HeartbeatResponse do
    @moduledoc "Response for heartbeat request"
    OpenApiSpex.schema(%{
      title: "HeartbeatResponse",
      description: "Response confirming heartbeat was recorded",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the heartbeat was recorded"},
        message: %Schema{type: :string, description: "Confirmation message"}
      },
      required: [:success, :message],
      example: %{
        "success" => true,
        "message" => "Heartbeat recorded"
      }
    })
  end

  defmodule OnlineCountResponse do
    @moduledoc "Response containing online user count"
    OpenApiSpex.schema(%{
      title: "OnlineCountResponse",
      description: "Response containing the count of online users",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :object,
          properties: %{
            online_count: %Schema{type: :integer, description: "Number of currently online users"},
            timestamp: %Schema{type: :string, format: :"date-time", description: "Timestamp of the count"}
          },
          required: [:online_count]
        }
      },
      required: [:success, :data],
      example: %{
        "success" => true,
        "data" => %{
          "online_count" => 1523,
          "timestamp" => "2024-01-15T10:30:00Z"
        }
      }
    })
  end
end
