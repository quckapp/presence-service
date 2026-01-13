defmodule PresenceService.PresenceTracker do
  use GenServer
  require Logger

  alias PresenceService.{Repo, RedisClient}
  alias Phoenix.PubSub

  @heartbeat_timeout 60_000  # 60 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  # Public API
  def heartbeat(user_id, workspace_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:heartbeat, user_id, workspace_id, metadata})
  end

  def update_status(user_id, status, custom_status \\ nil) do
    GenServer.call(__MODULE__, {:update_status, user_id, status, custom_status})
  end

  def get_presence(user_id) do
    # First check Redis cache
    case RedisClient.get_presence(user_id) do
      nil ->
        # Fallback to MongoDB
        case Repo.get_presence(user_id) do
          nil -> %{status: "offline"}
          presence -> presence
        end
      presence -> presence
    end
  end

  def get_batch_presence(user_ids) do
    # Get from Redis first
    cached = RedisClient.get_batch_presence(user_ids)
    cached_ids = Map.keys(cached)

    # Get missing from MongoDB
    missing_ids = user_ids -- cached_ids
    db_results = if Enum.empty?(missing_ids) do
      []
    else
      Repo.get_batch_presence(missing_ids)
      |> Enum.map(fn p -> {p["user_id"], p} end)
      |> Map.new()
    end

    # Merge results
    Map.merge(db_results, cached)
  end

  def join_channel(channel_id, user_id) do
    RedisClient.add_to_channel(channel_id, user_id)
    Repo.add_channel_presence(channel_id, user_id)
    broadcast_channel_update(channel_id, user_id, :joined)
  end

  def leave_channel(channel_id, user_id) do
    RedisClient.remove_from_channel(channel_id, user_id)
    Repo.remove_channel_presence(channel_id, user_id)
    broadcast_channel_update(channel_id, user_id, :left)
  end

  def get_channel_presence(channel_id) do
    user_ids = RedisClient.get_channel_members(channel_id)
    get_batch_presence(user_ids)
  end

  def get_workspace_online_users(workspace_id) do
    Repo.get_workspace_presence(workspace_id)
  end

  # GenServer callbacks
  @impl true
  def handle_cast({:heartbeat, user_id, workspace_id, metadata}, state) do
    now = DateTime.utc_now()

    presence_data = %{
      "user_id" => user_id,
      "workspace_id" => workspace_id,
      "status" => metadata[:status] || "online",
      "last_heartbeat" => now,
      "device" => metadata[:device],
      "platform" => metadata[:platform],
      "client_version" => metadata[:client_version]
    }

    # Update Redis cache
    RedisClient.set_presence(user_id, presence_data["status"])

    # Update MongoDB
    Repo.update_presence(user_id, presence_data)

    # Broadcast presence update
    broadcast_presence_update(user_id, workspace_id, presence_data)

    {:noreply, state}
  end

  @impl true
  def handle_call({:update_status, user_id, status, custom_status}, _from, state) do
    presence_data = %{
      "status" => status,
      "custom_status" => custom_status,
      "status_updated_at" => DateTime.utc_now()
    }

    # Update Redis
    RedisClient.set_presence(user_id, status)

    # Update MongoDB
    Repo.update_presence(user_id, presence_data)

    # Get workspace_id for broadcast
    case Repo.get_presence(user_id) do
      %{"workspace_id" => workspace_id} ->
        broadcast_presence_update(user_id, workspace_id, presence_data)
      _ -> :ok
    end

    {:reply, :ok, state}
  end

  defp broadcast_presence_update(user_id, workspace_id, presence_data) do
    PubSub.broadcast(
      PresenceService.PubSub,
      "presence:#{workspace_id}",
      {:presence_update, %{user_id: user_id, presence: presence_data}}
    )
  end

  defp broadcast_channel_update(channel_id, user_id, action) do
    PubSub.broadcast(
      PresenceService.PubSub,
      "channel:#{channel_id}",
      {:channel_presence, %{user_id: user_id, action: action}}
    )
  end
end
