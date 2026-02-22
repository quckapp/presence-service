defmodule PresenceService.Kafka.Consumer do
  @moduledoc "Kafka consumer for presence events from other services"
  @behaviour :brod_group_subscriber
  require Logger

  def start_link(_opts) do
    config = Application.get_env(:presence_service, :kafka)
    brokers = (config[:brokers] || ["localhost:9092"]) |> Enum.map(&parse_broker/1)
    group_id = config[:consumer_group] || "presence-service-group"

    state = %__MODULE__{
      circuit_state: :closed,
      failure_count: 0,
      last_failure_at: nil,
      processed_ids: MapSet.new()
    }

    # Schedule initial connection attempt
    send(self(), :connect)

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_kafka(state) do
      {:ok, new_state} ->
        Logger.info("[KafkaConsumer] Successfully connected to Kafka")
        {:noreply, %{new_state | circuit_state: :closed, failure_count: 0}}

      {:error, reason} ->
        new_state = handle_connection_failure(state, reason)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:retry_connect, state) do
    if state.circuit_state == :open do
      # Check if we should try to close the circuit
      if should_attempt_reset?(state) do
        Logger.info("[KafkaConsumer] Circuit half-open, attempting reconnect")
        send(self(), :connect)
        {:noreply, %{state | circuit_state: :half_open}}
      else
        schedule_retry()
        {:noreply, state}
      end
    else
      send(self(), :connect)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_dedup, state) do
    # Clean old entries from deduplication set
    cutoff = System.system_time(:millisecond) - @dedup_window_ms

    :ets.select_delete(:kafka_dedup, [
      {{:"$1", :"$2"}, [{:<, :"$2", cutoff}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    healthy = state.circuit_state == :closed and state.consumer_pid != nil
    {:reply, healthy, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      circuit_state: state.circuit_state,
      failure_count: state.failure_count,
      consumer_connected: state.consumer_pid != nil,
      dedup_size: :ets.info(:kafka_dedup, :size)
    }
    {:reply, stats, state}
  end

  # ============================================================================
  # Brod Callbacks - Group Subscriber
  # ============================================================================

  @doc "brod_group_subscriber callback - called when subscriber initializes"
  def init(_group_id, _init_args) do
    {:ok, %{}}
  end

  @doc """
  Handles incoming Kafka messages with deduplication and safe processing.
  """
  def handle_message(topic, partition, message, state) do
    message_id = extract_message_id(message)

    cond do
      # Skip if already processed (deduplication)
      is_duplicate?(message_id) ->
        Logger.debug("[KafkaConsumer] Skipping duplicate message: #{message_id}")
        {:ok, :ack, state}

      # Process the message
      true ->
        result = safe_process_message(topic, partition, message)
        mark_processed(message_id)

        case result do
          :ok -> {:ok, :ack, state}
          {:error, :retriable} -> {:ok, :ack_no_commit, state}
          {:error, _} -> {:ok, :ack, state}
        end
    end
  end

  # ============================================================================
  # Private Functions - Connection Management
  # ============================================================================

  defp connect_to_kafka(state) do
    config = Application.get_env(:presence_service, :kafka, [])

    brokers = parse_brokers(config[:brokers] || System.get_env("KAFKA_BROKERS") || "localhost:9092")
    group_id = config[:consumer_group] || "presence-service-group"
    topics = ["user-events", "connection-events"]
    client_id = :presence_consumer

    Logger.info("[KafkaConsumer] Connecting to brokers: #{inspect(brokers)}, group: #{group_id}")

    # Start brod client first (required before starting group subscriber)
    case :brod.start_client(brokers, client_id, []) do
      :ok ->
        start_group_subscriber(state, client_id, brokers, group_id, topics)

      {:error, {:already_started, _pid}} ->
        start_group_subscriber(state, client_id, brokers, group_id, topics)

      {:error, reason} ->
        Logger.error("[KafkaConsumer] Failed to start brod client: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_group_subscriber(state, client_id, brokers, group_id, topics) do
    group_config = [
      offset_commit_policy: :commit_to_kafka_v2,
      offset_commit_interval_seconds: 5,
      rejoin_delay_seconds: 2
    ]

    consumer_config = [begin_offset: :earliest]

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

  defp parse_brokers(brokers) when is_list(brokers) do
    Enum.map(brokers, fn
      {host, port} when is_list(host) -> {host, port}
      {host, port} when is_binary(host) -> {String.to_charlist(host), port}
      broker when is_binary(broker) -> parse_single_broker(broker)
    end)
  end

  defp parse_single_broker(broker) do
    case String.split(broker, ":") do
      [host, port] ->
        {String.to_charlist(host), String.to_integer(port)}

      [host] ->
        {String.to_charlist(host), 9092}
    end
  end

  # ============================================================================
  # Private Functions - Circuit Breaker
  # ============================================================================

  defp handle_connection_failure(state, reason) do
    new_failure_count = state.failure_count + 1
    Logger.warning("[KafkaConsumer] Connection failed (#{new_failure_count}/#{@max_failures}): #{inspect(reason)}")

    new_state = %{state |
      failure_count: new_failure_count,
      last_failure_at: System.system_time(:millisecond),
      consumer_pid: nil
    }

    if new_failure_count >= @max_failures do
      Logger.error("[KafkaConsumer] Circuit breaker OPEN - max failures reached")
      schedule_retry()
      %{new_state | circuit_state: :open}
    else
      schedule_retry()
      new_state
    end
  end

  defp should_attempt_reset?(state) do
    case state.last_failure_at do
      nil -> true
      last_failure ->
        elapsed = System.system_time(:millisecond) - last_failure
        elapsed >= @reset_timeout_ms
    end
  end

  defp schedule_retry do
    Process.send_after(self(), :retry_connect, @retry_delay_ms)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_dedup, @dedup_window_ms)
  end

  # ============================================================================
  # Private Functions - Message Processing
  # ============================================================================

  defp safe_process_message(topic, _partition, message) do
    with {:ok, payload} <- extract_payload(message),
         {:ok, event} <- Jason.decode(payload),
         :ok <- process_event(event) do
      :telemetry.execute(
        [:presence_service, :kafka, :message_processed],
        %{count: 1},
        %{topic: topic}
      )
      :ok
    else
      {:error, :invalid_json} ->
        Logger.warning("[KafkaConsumer] Invalid JSON in message")
        {:error, :invalid_json}

      {:error, :unknown_event} ->
        # Not an error, just unhandled event type
        :ok

      {:error, reason} ->
        Logger.error("[KafkaConsumer] Error processing message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_payload(message) when is_map(message), do: {:ok, message.value}
  defp extract_payload(message) when is_tuple(message), do: {:ok, elem(message, 4)}
  defp extract_payload(_), do: {:error, :invalid_message_format}

  defp extract_message_id(message) do
    case message do
      %{key: key} when is_binary(key) -> key
      %{offset: offset, partition: partition} -> "#{partition}-#{offset}"
      tuple when is_tuple(tuple) -> "#{elem(tuple, 1)}-#{elem(tuple, 2)}"
      _ -> :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
  end

  # ============================================================================
  # Private Functions - Event Handlers (Strategy Pattern)
  # ============================================================================

  defp process_event(%{"event" => "user_connected", "user_id" => user_id} = event) do
    metadata = Map.get(event, "metadata", %{})

    Task.start(fn ->
      PresenceService.PresenceManager.set_presence(user_id, :online, metadata)
    end)

    :ok
  end

  defp process_event(%{"event" => "user_disconnected", "user_id" => user_id}) do
    Task.start(fn ->
      PresenceService.PresenceManager.set_presence(user_id, :offline, %{reason: "kafka_event"})
    end)

    :ok
  end

  defp process_event(%{"event" => "status_update", "user_id" => user_id, "status" => status}) do
    case validate_status(status) do
      {:ok, status_atom} ->
        Task.start(fn ->
          PresenceService.PresenceManager.set_presence(user_id, status_atom, %{})
        end)
        :ok

      {:error, :invalid_status} ->
        Logger.warning("[KafkaConsumer] Invalid status received: #{status}")
        :ok
    end
  end

  defp process_event(%{"event" => event_type} = event) do
    Logger.debug("[KafkaConsumer] Unhandled event type: #{event_type}, payload: #{inspect(event)}")
    {:error, :unknown_event}
  end

  defp process_event(_event) do
    {:error, :unknown_event}
  end

  # ============================================================================
  # Private Functions - Validation
  # ============================================================================

  @doc """
  Safely validates and converts status string to atom.
  Uses a whitelist approach to prevent atom table exhaustion.
  """
  defp validate_status(status) when status in @valid_statuses do
    {:ok, String.to_existing_atom(status)}
  end

  defp validate_status(_status), do: {:error, :invalid_status}

  # ============================================================================
  # Private Functions - Deduplication
  # ============================================================================

  defp is_duplicate?(message_id) do
    case :ets.lookup(:kafka_dedup, message_id) do
      [{^message_id, _timestamp}] -> true
      [] -> false
    end
  end

  defp mark_processed(message_id) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(:kafka_dedup, {message_id, timestamp})
  end

  defp parse_broker({host, port}), do: {host, port}
end
