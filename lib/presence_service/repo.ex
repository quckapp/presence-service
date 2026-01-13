defmodule PresenceService.Repo do
  use GenServer

  @pool_name :mongo_pool

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    mongodb_config = Application.get_env(:presence_service, :mongodb)

    children = [
      %{
        id: :mongo_pool,
        start: {Mongo, :start_link, [[
          name: @pool_name,
          url: mongodb_config[:url],
          pool_size: mongodb_config[:pool_size] || 10
        ]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, %{}}
  end

  def get_pool, do: @pool_name

  # Presence operations
  def get_presence(user_id) do
    Mongo.find_one(@pool_name, "presence", %{"user_id" => user_id})
  end

  def update_presence(user_id, presence_data) do
    Mongo.update_one(
      @pool_name,
      "presence",
      %{"user_id" => user_id},
      %{"$set" => Map.merge(presence_data, %{"updated_at" => DateTime.utc_now()})},
      upsert: true
    )
  end

  def get_batch_presence(user_ids) do
    Mongo.find(@pool_name, "presence", %{"user_id" => %{"$in" => user_ids}})
    |> Enum.to_list()
  end

  def get_channel_presence(channel_id) do
    Mongo.find(@pool_name, "channel_presence", %{"channel_id" => channel_id})
    |> Enum.to_list()
  end

  def add_channel_presence(channel_id, user_id) do
    Mongo.update_one(
      @pool_name,
      "channel_presence",
      %{"channel_id" => channel_id, "user_id" => user_id},
      %{"$set" => %{"joined_at" => DateTime.utc_now()}},
      upsert: true
    )
  end

  def remove_channel_presence(channel_id, user_id) do
    Mongo.delete_one(@pool_name, "channel_presence", %{
      "channel_id" => channel_id,
      "user_id" => user_id
    })
  end

  def get_workspace_presence(workspace_id) do
    Mongo.find(@pool_name, "presence", %{"workspace_id" => workspace_id, "status" => %{"$ne" => "offline"}})
    |> Enum.to_list()
  end

  def save_presence_history(presence_record) do
    Mongo.insert_one(@pool_name, "presence_history", presence_record)
  end

  def cleanup_stale_presence(threshold_time) do
    Mongo.update_many(
      @pool_name,
      "presence",
      %{"last_heartbeat" => %{"$lt" => threshold_time}},
      %{"$set" => %{"status" => "offline", "updated_at" => DateTime.utc_now()}}
    )
  end
end
