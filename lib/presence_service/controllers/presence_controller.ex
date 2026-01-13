defmodule PresenceService.PresenceController do
  use Phoenix.Controller, formats: [:json]
  require Logger

  def show(conn, %{"user_id" => user_id}) do
    case PresenceService.PresenceManager.get_presence(user_id) do
      {:ok, presence} ->
        json(conn, %{success: true, data: presence})
      {:error, reason} ->
        conn |> put_status(404) |> json(%{success: false, error: reason})
    end
  end

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

  def bulk_get(conn, %{"user_ids" => user_ids}) when is_list(user_ids) do
    case PresenceService.PresenceManager.get_bulk_presence(user_ids) do
      {:ok, presences} ->
        json(conn, %{success: true, data: presences})
      {:error, reason} ->
        conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def heartbeat(conn, _params) do
    user_id = conn.assigns[:current_user_id]
    PresenceService.PresenceManager.heartbeat(user_id)
    json(conn, %{success: true, message: "Heartbeat recorded"})
  end

  def online_count(conn, _params) do
    case PresenceService.PresenceManager.online_count() do
      {:ok, count} ->
        json(conn, %{success: true, data: %{online_count: count}})
      {:error, reason} ->
        conn |> put_status(500) |> json(%{success: false, error: reason})
    end
  end
end
