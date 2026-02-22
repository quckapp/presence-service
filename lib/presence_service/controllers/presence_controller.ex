defmodule PresenceService.PresenceController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias PresenceService.Schemas.Presence
  alias PresenceService.Schemas.Common
  alias OpenApiSpex.Schema

  tags ["Presence"]
  security [%{"bearer_auth" => []}]

  operation :show,
    summary: "Get user presence",
    description: "Retrieves the current presence status for a specific user",
    parameters: [
      user_id: [
        in: :path,
        description: "The unique identifier of the user",
        type: :string,
        required: true,
        example: "user-123"
      ]
    ],
    responses: [
      ok: {"User presence retrieved successfully", "application/json", Presence.PresenceResponse},
      not_found: {"User not found", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized - Invalid or missing authentication", "application/json", Common.ErrorResponse}
    ]

  def show(conn, %{"user_id" => user_id}) do
    case PresenceService.PresenceManager.get_presence(user_id) do
      {:ok, presence} ->
        json(conn, %{success: true, data: presence})
      {:error, reason} ->
        conn |> put_status(404) |> json(%{success: false, error: reason})
    end
  end

  operation :update,
    summary: "Update presence",
    description: "Updates the current user's presence status. Requires authentication.",
    request_body: {"Presence update parameters", "application/json", Presence.UpdatePresenceRequest},
    responses: [
      ok: {"Presence updated successfully", "application/json", Presence.PresenceResponse},
      bad_request: {"Invalid request parameters", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized - Invalid or missing authentication", "application/json", Common.ErrorResponse}
    ]

  def update(conn, %{"status" => status} = params) do
    user_id = conn.assigns[:current_user_id]
    status_atom = String.to_existing_atom(status)
    metadata = Map.get(params, "metadata", %{})

    case PresenceService.PresenceManager.set_presence(user_id, status_atom, metadata) do
      {:ok, presence} ->
        json(conn, %{success: true, data: presence})
      {:error, reason} ->
        conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  rescue
    ArgumentError ->
      conn |> put_status(400) |> json(%{success: false, error: "Invalid status"})
  end

  operation :bulk_get,
    summary: "Bulk get presence",
    description: "Retrieves presence status for multiple users at once. Limited to 100 users per request.",
    request_body: {"List of user IDs", "application/json", Presence.BulkPresenceRequest},
    responses: [
      ok: {"Bulk presence retrieved successfully", "application/json", Presence.BulkPresenceResponse},
      bad_request: {"Invalid request parameters", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized - Invalid or missing authentication", "application/json", Common.ErrorResponse}
    ]

  def bulk_get(conn, %{"user_ids" => user_ids}) when is_list(user_ids) do
    case PresenceService.PresenceManager.get_bulk_presence(user_ids) do
      {:ok, presences} ->
        json(conn, %{success: true, data: presences})
      {:error, reason} ->
        conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :heartbeat,
    summary: "Send heartbeat",
    description: "Sends a heartbeat to indicate the user is still active. Should be called periodically to maintain online status.",
    request_body: {"Heartbeat parameters", "application/json", Presence.HeartbeatRequest},
    responses: [
      ok: {"Heartbeat recorded successfully", "application/json", Presence.HeartbeatResponse},
      unauthorized: {"Unauthorized - Invalid or missing authentication", "application/json", Common.ErrorResponse}
    ]

  def heartbeat(conn, _params) do
    user_id = conn.assigns[:current_user_id]
    PresenceService.PresenceManager.heartbeat(user_id)
    json(conn, %{success: true, message: "Heartbeat recorded"})
  end

  operation :online_count,
    summary: "Get online count",
    description: "Returns the total count of currently online users",
    responses: [
      ok: {"Online count retrieved successfully", "application/json", Presence.OnlineCountResponse},
      internal_server_error: {"Internal server error", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized - Invalid or missing authentication", "application/json", Common.ErrorResponse}
    ]

  def online_count(conn, _params) do
    case PresenceService.PresenceManager.online_count() do
      {:ok, count} ->
        json(conn, %{success: true, data: %{online_count: count}})
      {:error, reason} ->
        conn |> put_status(500) |> json(%{success: false, error: reason})
    end
  end
end
