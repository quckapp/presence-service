defmodule PresenceService.Kafka.Consumer do
  @moduledoc "Kafka consumer for presence events from other services"
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:presence_service, :kafka)
    brokers = config[:brokers] |> Enum.map(&parse_broker/1)
    group_id = config[:consumer_group]

    group_config = [
      offset_commit_policy: :commit_to_kafka_v2,
      offset_commit_interval_seconds: 5
    ]

    topics = ["user-events", "connection-events"]

    case :brod.start_link_group_subscriber(
      :presence_consumer,
      brokers,
      group_id,
      topics,
      group_config,
      __MODULE__,
      []
    ) do
      {:ok, pid} ->
        Logger.info("Kafka consumer started successfully")
        {:ok, %{consumer_pid: pid}}
      {:error, reason} ->
        Logger.warning("Kafka consumer failed to start: #{inspect(reason)}")
        {:ok, %{consumer_pid: nil}}
    end
  end

  def handle_message(_topic, _partition, message, state) do
    case Jason.decode(message.value) do
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
