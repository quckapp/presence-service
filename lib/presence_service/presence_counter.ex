defmodule PresenceService.PresenceCounter do
  @moduledoc """
  HyperLogLog-based presence counter using hypex.

  Provides approximate counting for large-scale presence tracking:
  - Online users per workspace (O(1) instead of O(n))
  - Active channels count
  - Unique visitors

  HyperLogLog provides:
  - Constant memory usage (~12KB for billions of items)
  - ~2% error rate for cardinality estimates
  - O(1) add and count operations

  ## Usage:

      # Track user online
      PresenceCounter.add_online_user(workspace_id, user_id)

      # Get approximate online count
      {:ok, count} = PresenceCounter.online_count(workspace_id)

      # Track channel activity
      PresenceCounter.add_channel_member(channel_id, user_id)

  ## Persistence:
  HyperLogLog structures are periodically persisted to Redis for durability.
  """

  use GenServer
  require Logger

  alias PresenceService.{RedisClient, CircuitBreaker}

  @persist_interval 30_000  # 30 seconds
  @precision 14             # HyperLogLog precision (14 = ~16KB, ~0.81% error)
  @cleanup_interval 300_000 # 5 minutes

  defstruct [
    :workspace_hlls,    # workspace_id => HLL struct
    :channel_hlls,      # channel_id => HLL struct
    :last_persist,
    :timer_refs
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a user to the online count for a workspace.
  """
  def add_online_user(workspace_id, user_id) do
    GenServer.cast(__MODULE__, {:add_online, workspace_id, user_id})
  end

  @doc """
  Remove a user from the online count for a workspace.
  Note: HyperLogLog doesn't support removal. This triggers a rebuild
  from the authoritative source (Redis set) on next count.
  """
  def remove_online_user(workspace_id, _user_id) do
    GenServer.cast(__MODULE__, {:invalidate, workspace_id})
  end

  @doc """
  Get approximate online count for a workspace.
  Uses HyperLogLog for O(1) counting.
  """
  def online_count(workspace_id) do
    GenServer.call(__MODULE__, {:online_count, workspace_id})
  end

  @doc """
  Add a user to channel member count.
  """
  def add_channel_member(channel_id, user_id) do
    GenServer.cast(__MODULE__, {:add_channel_member, channel_id, user_id})
  end

  @doc """
  Get approximate channel member count.
  """
  def channel_member_count(channel_id) do
    GenServer.call(__MODULE__, {:channel_count, channel_id})
  end

  @doc """
  Get counts for multiple workspaces.
  """
  def batch_online_counts(workspace_ids) when is_list(workspace_ids) do
    GenServer.call(__MODULE__, {:batch_counts, workspace_ids})
  end

  @doc """
  Force persistence of all HLLs to Redis.
  """
  def persist_all do
    GenServer.call(__MODULE__, :persist_all)
  end

  @doc """
  Get current statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Schedule periodic persistence
    persist_ref = Process.send_after(self(), :persist, @persist_interval)
    cleanup_ref = Process.send_after(self(), :cleanup, @cleanup_interval)

    state = %__MODULE__{
      workspace_hlls: %{},
      channel_hlls: %{},
      last_persist: DateTime.utc_now(),
      timer_refs: %{persist: persist_ref, cleanup: cleanup_ref}
    }

    Logger.info("[PresenceCounter] Started with precision #{@precision}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:add_online, workspace_id, user_id}, state) do
    hll = get_or_create_hll(state.workspace_hlls, workspace_id)
    updated_hll = Hypex.update(hll, to_string(user_id))
    new_hlls = Map.put(state.workspace_hlls, workspace_id, updated_hll)

    {:noreply, %{state | workspace_hlls: new_hlls}}
  end

  @impl true
  def handle_cast({:add_channel_member, channel_id, user_id}, state) do
    hll = get_or_create_hll(state.channel_hlls, channel_id)
    updated_hll = Hypex.update(hll, to_string(user_id))
    new_hlls = Map.put(state.channel_hlls, channel_id, updated_hll)

    {:noreply, %{state | channel_hlls: new_hlls}}
  end

  @impl true
  def handle_cast({:invalidate, workspace_id}, state) do
    # Remove the HLL so it gets rebuilt on next access
    new_hlls = Map.delete(state.workspace_hlls, workspace_id)
    {:noreply, %{state | workspace_hlls: new_hlls}}
  end

  @impl true
  def handle_call({:online_count, workspace_id}, _from, state) do
    case Map.get(state.workspace_hlls, workspace_id) do
      nil ->
        # No HLL exists, try to load from Redis or return 0
        count = load_count_from_redis(workspace_id)
        {:reply, {:ok, count}, state}

      hll ->
        count = Hypex.cardinality(hll) |> round()
        {:reply, {:ok, count}, state}
    end
  end

  @impl true
  def handle_call({:channel_count, channel_id}, _from, state) do
    case Map.get(state.channel_hlls, channel_id) do
      nil ->
        {:reply, {:ok, 0}, state}

      hll ->
        count = Hypex.cardinality(hll) |> round()
        {:reply, {:ok, count}, state}
    end
  end

  @impl true
  def handle_call({:batch_counts, workspace_ids}, _from, state) do
    counts = Enum.map(workspace_ids, fn workspace_id ->
      count = case Map.get(state.workspace_hlls, workspace_id) do
        nil -> 0
        hll -> Hypex.cardinality(hll) |> round()
      end
      {workspace_id, count}
    end)
    |> Map.new()

    {:reply, {:ok, counts}, state}
  end

  @impl true
  def handle_call(:persist_all, _from, state) do
    persist_to_redis(state)
    {:reply, :ok, %{state | last_persist: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      workspace_count: map_size(state.workspace_hlls),
      channel_count: map_size(state.channel_hlls),
      last_persist: state.last_persist,
      precision: @precision,
      memory_estimate_kb: estimate_memory(state)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:persist, state) do
    persist_to_redis(state)

    # Schedule next persistence
    persist_ref = Process.send_after(self(), :persist, @persist_interval)
    timer_refs = %{state.timer_refs | persist: persist_ref}

    {:noreply, %{state | last_persist: DateTime.utc_now(), timer_refs: timer_refs}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Clean up old/empty HLLs
    new_workspace_hlls = cleanup_hlls(state.workspace_hlls)
    new_channel_hlls = cleanup_hlls(state.channel_hlls)

    # Schedule next cleanup
    cleanup_ref = Process.send_after(self(), :cleanup, @cleanup_interval)
    timer_refs = %{state.timer_refs | cleanup: cleanup_ref}

    {:noreply, %{state |
      workspace_hlls: new_workspace_hlls,
      channel_hlls: new_channel_hlls,
      timer_refs: timer_refs
    }}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Persist on shutdown
    persist_to_redis(state)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_or_create_hll(hlls, key) do
    case Map.get(hlls, key) do
      nil -> Hypex.new(@precision)
      hll -> hll
    end
  end

  defp load_count_from_redis(workspace_id) do
    # Fallback to Redis for exact count if HLL not available
    CircuitBreaker.call(:redis, fn ->
      RedisClient.get_workspace_online_count(workspace_id)
    end, default: 0)
  end

  defp persist_to_redis(state) do
    # Persist workspace counts
    Enum.each(state.workspace_hlls, fn {workspace_id, hll} ->
      count = Hypex.cardinality(hll) |> round()

      CircuitBreaker.call(:redis, fn ->
        key = "presence:hll:workspace:#{workspace_id}"
        # Store the serialized HLL and the count
        binary = :erlang.term_to_binary(hll)
        RedisClient.command(["SET", key, binary])
        RedisClient.command(["SET", "presence:hll:count:#{workspace_id}", to_string(count)])
      end, default: :ok)
    end)

    Logger.debug("[PresenceCounter] Persisted #{map_size(state.workspace_hlls)} HLLs to Redis")
  end

  defp cleanup_hlls(hlls) do
    # Remove HLLs with zero or very low cardinality
    Enum.filter(hlls, fn {_key, hll} ->
      Hypex.cardinality(hll) > 0
    end)
    |> Map.new()
  end

  defp estimate_memory(state) do
    # Each HLL with precision 14 uses ~16KB
    hll_count = map_size(state.workspace_hlls) + map_size(state.channel_hlls)
    hll_count * 16
  end
end
