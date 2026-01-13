defmodule PresenceService.PresenceManager do
  @moduledoc """
  Core Presence Manager - Handles user presence state with distributed tracking.
  Uses Horde for distributed registry and MongoDB for persistence.
  """
  use GenServer
  require Logger

  @heartbeat_interval 30_000  # 30 seconds
  @offline_timeout 90_000     # 90 seconds
  @status_types [:online, :away, :busy, :offline, :invisible]

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Set user presence status"
  def set_presence(user_id, status, metadata \ %{}) when status in @status_types do
    GenServer.call(__MODULE__, {:set_presence, user_id, status, metadata})
  end

  @doc "Get user presence status"
  def get_presence(user_id) do
    GenServer.call(__MODULE__, {:get_presence, user_id})
  end

  @doc "Get presence for multiple users"
  def get_bulk_presence(user_ids) when is_list(user_ids) do
    GenServer.call(__MODULE__, {:get_bulk_presence, user_ids})
  end

  @doc "Record heartbeat to keep user online"
  def heartbeat(user_id) do
    GenServer.cast(__MODULE__, {:heartbeat, user_id})
  end

  @doc "Subscribe to presence updates for a user"
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(PresenceService.PubSub, "presence:#{user_id}")
  end

  @doc "Get online users count"
  def online_count do
    GenServer.call(__MODULE__, :online_count)
  end

  # Server Callbacks

  @impl true
  def init(_state) do
    schedule_cleanup()
    {:ok, %{users: %{}}}
  end

  @impl true
  def handle_call({:set_presence, user_id, status, metadata}, _from, state) do
    start_time = System.monotonic_time()
    
    presence = %{
      user_id: user_id,
      status: status,
      last_seen: DateTime.utc_now(),
      metadata: metadata,
      device: Map.get(metadata, :device, "unknown"),
      platform: Map.get(metadata, :platform, "unknown")
    }

    # Store in MongoDB
    store_presence_mongo(presence)
    
    # Cache in Redis for fast lookups
    cache_presence_redis(user_id, presence)
    
    # Update local state
    new_state = put_in(state, [:users, user_id], presence)
    
    # Broadcast presence change
    broadcast_presence_change(user_id, status, presence)
    
    # Emit telemetry
    :telemetry.execute([:presence, :status, :update], %{duration: System.monotonic_time() - start_time}, %{user_id: user_id, status: status})
    :telemetry.execute([:presence, :user, :connected], %{count: 1}, %{}) |> then(fn _ -> nil end)
    
    Logger.info("User #{user_id} status changed to #{status}")
    
    {:reply, {:ok, presence}, new_state}
  end

  @impl true
  def handle_call({:get_presence, user_id}, _from, state) do
    # Try local cache first, then Redis, then MongoDB
    presence = 
      case Map.get(state.users, user_id) do
        nil -> get_presence_from_cache_or_db(user_id)
        p -> p
      end
    
    {:reply, {:ok, presence}, state}
  end

  @impl true
  def handle_call({:get_bulk_presence, user_ids}, _from, state) do
    presences = Enum.map(user_ids, fn user_id ->
      case Map.get(state.users, user_id) do
        nil -> get_presence_from_cache_or_db(user_id)
        p -> p
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    {:reply, {:ok, presences}, state}
  end

  @impl true
  def handle_call(:online_count, _from, state) do
    count = state.users
    |> Map.values()
    |> Enum.count(fn p -> p.status in [:online, :away, :busy] end)
    
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_cast({:heartbeat, user_id}, state) do
    new_state = update_in(state, [:users, user_id], fn
      nil -> nil
      presence -> %{presence | last_seen: DateTime.utc_now()}
    end)
    
    # Update Redis TTL
    Redix.command(:presence_redis, ["EXPIRE", "presence:#{user_id}", 120])
    
    :telemetry.execute([:presence, :heartbeat], %{count: 1}, %{user_id: user_id})
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_stale, state) do
    now = DateTime.utc_now()
    
    new_users = state.users
    |> Enum.reject(fn {_user_id, presence} ->
      diff = DateTime.diff(now, presence.last_seen, :millisecond)
      diff > @offline_timeout and presence.status != :offline
    end)
    |> Enum.into(%{})
    
    # Mark stale users as offline
    stale_users = Map.keys(state.users) -- Map.keys(new_users)
    Enum.each(stale_users, fn user_id ->
      set_presence(user_id, :offline, %{reason: "timeout"})
    end)
    
    schedule_cleanup()
    {:noreply, %{state | users: new_users}}
  end

  # Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale, @heartbeat_interval)
  end

  defp store_presence_mongo(presence) do
    Mongo.update_one(
      :presence_mongo,
      "presences",
      %{user_id: presence.user_id},
      %{"$set" => presence},
      upsert: true
    )
  end

  defp cache_presence_redis(user_id, presence) do
    json = Jason.encode!(presence)
    Redix.command(:presence_redis, ["SETEX", "presence:#{user_id}", 120, json])
  end

  defp get_presence_from_cache_or_db(user_id) do
    # Try Redis first
    case Redix.command(:presence_redis, ["GET", "presence:#{user_id}"]) do
      {:ok, nil} -> get_presence_from_mongo(user_id)
      {:ok, json} -> Jason.decode!(json, keys: :atoms)
      _ -> get_presence_from_mongo(user_id)
    end
  end

  defp get_presence_from_mongo(user_id) do
    case Mongo.find_one(:presence_mongo, "presences", %{user_id: user_id}) do
      nil -> %{user_id: user_id, status: :offline, last_seen: nil}
      doc -> 
        %{
          user_id: doc["user_id"],
          status: String.to_existing_atom(doc["status"] || "offline"),
          last_seen: doc["last_seen"],
          metadata: doc["metadata"] || %{}
        }
    end
  end

  defp broadcast_presence_change(user_id, status, presence) do
    Phoenix.PubSub.broadcast(
      PresenceService.PubSub,
      "presence:#{user_id}",
      {:presence_change, user_id, status, presence}
    )
    
    # Also broadcast to Kafka for other services
    PresenceService.Kafka.Producer.publish_presence_event(%{
      event: "presence_changed",
      user_id: user_id,
      status: status,
      timestamp: DateTime.utc_now()
    })
  end
end
