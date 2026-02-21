defmodule PresenceService.Kafka.Consumer do
  @moduledoc "Kafka consumer for presence events from other services"
  @behaviour :brod_group_subscriber
  require Logger

  def start_link(_opts) do
    config = Application.get_env(:presence_service, :kafka)
    brokers = (config[:brokers] || ["localhost:9092"]) |> Enum.map(&parse_broker/1)
    group_id = config[:consumer_group] || "presence-service-group"

    group_config = [
      offset_commit_policy: :commit_to_kafka_v2,
      offset_commit_interval_seconds: 5
    ]

    topics = ["user-events", "connection-events"]

    case :brod.start_client(brokers, :presence_consumer, _client_config = []) do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} ->
        Logger.warning("Kafka client failed to start: #{inspect(reason)}")
        :ignore
    end
    |> case do
      :ok ->
        :brod.start_link_group_subscriber(
          :presence_consumer,
          group_id,
          topics,
          group_config,
          _consumer_config = [begin_offset: :latest],
          __MODULE__,
          _cb_init_arg = []
        )
      :ignore -> :ignore
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl :brod_group_subscriber
  def init(_group_id, _cb_init_arg) do
    Logger.info("Kafka consumer started successfully")
    {:ok, %{}}
  end

  @impl :brod_group_subscriber
  def handle_message(_topic, _partition, message, state) do
    value = :brod.message_value(message)

    case Jason.decode(value) do
      {:ok, event} -> process_event(event)
      {:error, _} -> Logger.warning("Invalid JSON in Kafka message")
    end

    {:ok, :ack, state}
  end

  defp process_event(%{"event" => "user_connected", "user_id" => user_id} = event) do
    metadata = Map.get(event, "metadata", %{})
    PresenceService.PresenceManager.set_presence(user_id, :online, metadata)
  end

  defp process_event(%{"event" => "user_disconnected", "user_id" => user_id}) do
    PresenceService.PresenceManager.set_presence(user_id, :offline, %{reason: "kafka_event"})
  end

  defp process_event(%{"event" => "status_update", "user_id" => user_id, "status" => status}) do
    status_atom = String.to_existing_atom(status)
    PresenceService.PresenceManager.set_presence(user_id, status_atom, %{})
  end

  defp process_event(event) do
    Logger.debug("Unhandled Kafka event: #{inspect(event)}")
  end

  defp parse_broker(broker) when is_binary(broker) do
    [host, port] = String.split(broker, ":")
    {host, String.to_integer(port)}
  end

  defp parse_broker({host, port}), do: {host, port}
end
