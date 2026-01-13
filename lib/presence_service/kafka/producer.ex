defmodule PresenceService.Kafka.Producer do
  @moduledoc "Kafka producer for publishing presence events"
  require Logger

  @topic "presence-events"

  def publish_presence_event(event) do
    config = Application.get_env(:presence_service, :kafka)
    brokers = config[:brokers] |> Enum.map(&parse_broker/1)

    message = Jason.encode!(event)
    partition_key = Map.get(event, :user_id, "default")

    case :brod.produce_sync(brokers, @topic, partition_fun(partition_key), partition_key, message) do
      :ok -> {:ok, :published}
      {:error, reason} ->
        Logger.warning("Failed to publish to Kafka: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp partition_fun(key) do
    :erlang.phash2(key, 3)  # 3 partitions
  end

  defp parse_broker(broker) when is_binary(broker) do
    [host, port] = String.split(broker, ":")
    {host, String.to_integer(port)}
  end
  defp parse_broker({host, port}), do: {host, port}
end
