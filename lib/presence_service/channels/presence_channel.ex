defmodule PresenceService.PresenceChannel do
  use Phoenix.Channel
  alias PresenceService.Actors.UserSession
  require Logger

  @impl true
  def join("presence:lobby", _params, socket) do
    user_id = socket.assigns.user_id
    
    # Start user session actor
    case Horde.DynamicSupervisor.start_child(
      PresenceService.PresenceSupervisor,
      {UserSession, [user_id: user_id, socket_pid: self(), metadata: %{channel: "lobby"}]}
    ) do
      {:ok, _pid} -> Logger.info("User #{user_id} joined presence lobby")
      {:error, {:already_started, _pid}} -> Logger.info("User #{user_id} reconnected")
      error -> Logger.warning("Failed to start session: #{inspect(error)}")
    end

    send(self(), :after_join)
    {:ok, socket}
  end

  def join("presence:" <> target_user_id, _params, socket) do
    # Subscribe to specific user's presence
    PresenceService.PresenceManager.subscribe(target_user_id)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id
    {:ok, presence} = PresenceService.PresenceManager.get_presence(user_id)
    push(socket, "presence_state", %{presence: presence})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:presence_change, user_id, status, presence}, socket) do
    push(socket, "presence_change", %{user_id: user_id, status: status, presence: presence})
    {:noreply, socket}
  end

  @impl true
  def handle_in("update_status", %{"status" => status}, socket) do
    user_id = socket.assigns.user_id
    status_atom = String.to_existing_atom(status)
    UserSession.update_status(user_id, status_atom)
    {:reply, :ok, socket}
  rescue
    ArgumentError -> {:reply, {:error, %{reason: "Invalid status"}}, socket}
  end

  @impl true
  def handle_in("heartbeat", _params, socket) do
    user_id = socket.assigns.user_id
    UserSession.record_activity(user_id)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("get_presence", %{"user_ids" => user_ids}, socket) do
    {:ok, presences} = PresenceService.PresenceManager.get_bulk_presence(user_ids)
    {:reply, {:ok, %{presences: presences}}, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    user_id = socket.assigns.user_id
    UserSession.disconnect(user_id)
    :ok
  end
end
