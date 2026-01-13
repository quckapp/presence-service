defmodule PresenceService.Plugs.AuthPlug do
  @moduledoc "JWT Authentication Plug"
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_token(conn) do
      {:ok, token} ->
        case PresenceService.Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            assign(conn, :current_user_id, claims["sub"])
          {:error, _reason} ->
            conn |> put_status(401) |> json(%{error: "Invalid token"}) |> halt()
        end
      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "Missing authorization"}) |> halt()
    end
  end

  defp get_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end
end
