defmodule PresenceService.RedisClient do
  use GenServer

  @pool_size 5
  @prefix "presence:"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    redis_url = Application.get_env(:presence_service, :redis)[:url]

    children =
      for i <- 0..(@pool_size - 1) do
        Supervisor.child_spec(
          {Redix, {redis_url, [name: :"redix_#{i}"]}},
          id: {Redix, i}
        )
      end

    Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, %{}}
  end

  defp command(args) do
    Redix.command(:"redix_#{:rand.uniform(@pool_size) - 1}", args)
  end

  # Real-time presence cache
  def set_presence(user_id, status, ttl \\ 120) do
    key = "#{@prefix}user:#{user_id}"
    data = Jason.encode!(%{status: status, timestamp: System.system_time(:second)})
    command(["SETEX", key, ttl, data])
  end

  def get_presence(user_id) do
    key = "#{@prefix}user:#{user_id}"
    case command(["GET", key]) do
      {:ok, nil} -> nil
      {:ok, data} -> Jason.decode!(data)
      _ -> nil
    end
  end

  def get_batch_presence(user_ids) do
    keys = Enum.map(user_ids, &"#{@prefix}user:#{&1}")
    case command(["MGET" | keys]) do
      {:ok, results} ->
        user_ids
        |> Enum.zip(results)
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.map(fn {id, data} -> {id, Jason.decode!(data)} end)
        |> Map.new()
      _ -> %{}
    end
  end

  def delete_presence(user_id) do
    key = "#{@prefix}user:#{user_id}"
    command(["DEL", key])
  end

  # Channel presence tracking
  def add_to_channel(channel_id, user_id) do
    key = "#{@prefix}channel:#{channel_id}"
    command(["SADD", key, user_id])
  end

  def remove_from_channel(channel_id, user_id) do
    key = "#{@prefix}channel:#{channel_id}"
    command(["SREM", key, user_id])
  end

  def get_channel_members(channel_id) do
    key = "#{@prefix}channel:#{channel_id}"
    case command(["SMEMBERS", key]) do
      {:ok, members} -> members
      _ -> []
    end
  end

  def get_channel_count(channel_id) do
    key = "#{@prefix}channel:#{channel_id}"
    case command(["SCARD", key]) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  # Typing indicators
  def set_typing(channel_id, user_id, ttl \\ 10) do
    key = "#{@prefix}typing:#{channel_id}"
    command(["ZADD", key, System.system_time(:second) + ttl, user_id])
    command(["EXPIRE", key, ttl + 5])
  end

  def get_typing_users(channel_id) do
    key = "#{@prefix}typing:#{channel_id}"
    now = System.system_time(:second)
    case command(["ZRANGEBYSCORE", key, now, "+inf"]) do
      {:ok, users} -> users
      _ -> []
    end
  end

  def clear_typing(channel_id, user_id) do
    key = "#{@prefix}typing:#{channel_id}"
    command(["ZREM", key, user_id])
  end

  # Online users count
  def increment_workspace_online(workspace_id) do
    key = "#{@prefix}workspace:#{workspace_id}:online"
    command(["INCR", key])
  end

  def decrement_workspace_online(workspace_id) do
    key = "#{@prefix}workspace:#{workspace_id}:online"
    command(["DECR", key])
  end

  def get_workspace_online_count(workspace_id) do
    key = "#{@prefix}workspace:#{workspace_id}:online"
    case command(["GET", key]) do
      {:ok, nil} -> 0
      {:ok, count} -> String.to_integer(count)
      _ -> 0
    end
  end
end
