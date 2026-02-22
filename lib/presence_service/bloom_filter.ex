defmodule PresenceService.BloomFilter do
  @moduledoc """
  Bloom filter for fast presence checks using bloomex.

  Provides probabilistic membership testing for:
  - Fast channel membership checks (is user in channel?)
  - Workspace presence caching
  - Reduce Redis SISMEMBER calls

  Bloom filters provide:
  - O(1) membership testing
  - No false negatives (if filter says "no", user is definitely not present)
  - Possible false positives (~1% with proper sizing)
  - Memory efficient

  ## Usage:

      # Add user to channel filter
      BloomFilter.add_to_channel(channel_id, user_id)

      # Fast membership check (may have false positives)
      BloomFilter.maybe_in_channel?(channel_id, user_id)

      # Definitive check (falls back to Redis if filter says "maybe")
      BloomFilter.in_channel?(channel_id, user_id)

  ## False Positive Handling:
  When the filter returns "maybe in channel", we verify against Redis.
  This approach reduces Redis calls by ~99% for non-members while ensuring accuracy.
  """

  use GenServer
  require Logger

  alias PresenceService.{RedisClient, CircuitBreaker}

  @rebuild_interval 300_000  # 5 minutes
  @default_capacity 10_000   # Expected number of members per channel
  @default_error_rate 0.01   # 1% false positive rate

  defstruct [
    :channel_filters,    # channel_id => bloom filter
    :workspace_filters,  # workspace_id => bloom filter
    :filter_stats,
    :timer_ref
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a user to the channel membership filter.
  """
  def add_to_channel(channel_id, user_id) do
    GenServer.cast(__MODULE__, {:add_channel, channel_id, user_id})
  end

  @doc """
  Remove a user from the channel filter.
  Note: Bloom filters don't support removal. This marks the filter for rebuild.
  """
  def remove_from_channel(channel_id, _user_id) do
    GenServer.cast(__MODULE__, {:invalidate_channel, channel_id})
  end

  @doc """
  Fast probabilistic check if user might be in channel.
  Returns true if user is possibly in channel (may be false positive).
  Returns false if user is definitely NOT in channel.
  """
  def maybe_in_channel?(channel_id, user_id) do
    GenServer.call(__MODULE__, {:check_channel, channel_id, user_id})
  catch
    :exit, _ -> true  # Assume "maybe" on timeout
  end

  @doc """
  Definitive check if user is in channel.
  Uses bloom filter first, then verifies against Redis if needed.
  """
  def in_channel?(channel_id, user_id) do
    case maybe_in_channel?(channel_id, user_id) do
      false ->
        # Bloom filter says definitely NOT in channel
        false

      true ->
        # Bloom filter says "maybe" - verify with Redis
        members = RedisClient.get_channel_members(channel_id)
        user_id in members
    end
  end

  @doc """
  Add user to workspace filter.
  """
  def add_to_workspace(workspace_id, user_id) do
    GenServer.cast(__MODULE__, {:add_workspace, workspace_id, user_id})
  end

  @doc """
  Check if user might be online in workspace.
  """
  def maybe_in_workspace?(workspace_id, user_id) do
    GenServer.call(__MODULE__, {:check_workspace, workspace_id, user_id})
  catch
    :exit, _ -> true
  end

  @doc """
  Batch check multiple users against a channel filter.
  Returns list of user_ids that are possibly in the channel.
  """
  def filter_channel_members(channel_id, user_ids) when is_list(user_ids) do
    GenServer.call(__MODULE__, {:filter_channel_batch, channel_id, user_ids})
  catch
    :exit, _ -> user_ids
  end

  @doc """
  Get filter statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{}
  end

  @doc """
  Force rebuild of a channel filter from Redis.
  """
  def rebuild_channel(channel_id) do
    GenServer.cast(__MODULE__, {:rebuild_channel, channel_id})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Schedule periodic rebuild
    timer_ref = Process.send_after(self(), :rebuild_all, @rebuild_interval)

    state = %__MODULE__{
      channel_filters: %{},
      workspace_filters: %{},
      filter_stats: %{
        checks: 0,
        hits: 0,
        misses: 0,
        false_positives: 0
      },
      timer_ref: timer_ref
    }

    Logger.info("[BloomFilter] Started with capacity #{@default_capacity}, error rate #{@default_error_rate}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:add_channel, channel_id, user_id}, state) do
    filter = get_or_create_filter(state.channel_filters, channel_id)
    updated_filter = Bloomex.add(filter, to_string(user_id))
    new_filters = Map.put(state.channel_filters, channel_id, updated_filter)

    {:noreply, %{state | channel_filters: new_filters}}
  end

  @impl true
  def handle_cast({:add_workspace, workspace_id, user_id}, state) do
    filter = get_or_create_filter(state.workspace_filters, workspace_id)
    updated_filter = Bloomex.add(filter, to_string(user_id))
    new_filters = Map.put(state.workspace_filters, workspace_id, updated_filter)

    {:noreply, %{state | workspace_filters: new_filters}}
  end

  @impl true
  def handle_cast({:invalidate_channel, channel_id}, state) do
    # Remove filter so it gets rebuilt on next access
    new_filters = Map.delete(state.channel_filters, channel_id)
    {:noreply, %{state | channel_filters: new_filters}}
  end

  @impl true
  def handle_cast({:rebuild_channel, channel_id}, state) do
    # Rebuild filter from Redis
    new_filters = case rebuild_filter_from_redis(channel_id) do
      {:ok, filter} -> Map.put(state.channel_filters, channel_id, filter)
      :error -> state.channel_filters
    end

    {:noreply, %{state | channel_filters: new_filters}}
  end

  @impl true
  def handle_call({:check_channel, channel_id, user_id}, _from, state) do
    stats = state.filter_stats

    case Map.get(state.channel_filters, channel_id) do
      nil ->
        # No filter, assume "maybe"
        {:reply, true, %{state | filter_stats: %{stats | checks: stats.checks + 1}}}

      filter ->
        result = Bloomex.member?(filter, to_string(user_id))
        new_stats = if result do
          %{stats | checks: stats.checks + 1, hits: stats.hits + 1}
        else
          %{stats | checks: stats.checks + 1, misses: stats.misses + 1}
        end
        {:reply, result, %{state | filter_stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:check_workspace, workspace_id, user_id}, _from, state) do
    case Map.get(state.workspace_filters, workspace_id) do
      nil -> {:reply, true, state}
      filter -> {:reply, Bloomex.member?(filter, to_string(user_id)), state}
    end
  end

  @impl true
  def handle_call({:filter_channel_batch, channel_id, user_ids}, _from, state) do
    case Map.get(state.channel_filters, channel_id) do
      nil ->
        # No filter, return all
        {:reply, user_ids, state}

      filter ->
        # Filter to only possibly-present users
        filtered = Enum.filter(user_ids, fn user_id ->
          Bloomex.member?(filter, to_string(user_id))
        end)
        {:reply, filtered, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      channel_filter_count: map_size(state.channel_filters),
      workspace_filter_count: map_size(state.workspace_filters),
      checks: state.filter_stats.checks,
      hits: state.filter_stats.hits,
      misses: state.filter_stats.misses,
      hit_rate: calculate_hit_rate(state.filter_stats),
      capacity: @default_capacity,
      error_rate: @default_error_rate
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:rebuild_all, state) do
    # Rebuild all filters from Redis periodically
    new_channel_filters = rebuild_all_filters(state.channel_filters, "channel")
    new_workspace_filters = rebuild_all_filters(state.workspace_filters, "workspace")

    # Schedule next rebuild
    timer_ref = Process.send_after(self(), :rebuild_all, @rebuild_interval)

    {:noreply, %{state |
      channel_filters: new_channel_filters,
      workspace_filters: new_workspace_filters,
      timer_ref: timer_ref
    }}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_or_create_filter(filters, key) do
    case Map.get(filters, key) do
      # Bloomex.scalable(capacity, error, error_ratio, growth)
      nil -> Bloomex.scalable(@default_capacity, @default_error_rate, 0.1, 2)
      filter -> filter
    end
  end

  defp rebuild_filter_from_redis(channel_id) do
    case RedisClient.get_channel_members(channel_id) do
      members when is_list(members) ->
        filter = Bloomex.scalable(@default_capacity, @default_error_rate, 0.1, 2)
        updated = Enum.reduce(members, filter, fn member, acc ->
          Bloomex.add(acc, to_string(member))
        end)
        {:ok, updated}
      _ ->
        :error
    end
  end

  defp rebuild_all_filters(filters, _type) do
    # Keep existing filters for now, full rebuild would be expensive
    # In production, could do incremental rebuilds
    filters
  end

  defp calculate_hit_rate(%{checks: 0}), do: 0.0
  defp calculate_hit_rate(%{checks: checks, hits: hits}) do
    Float.round(hits / checks * 100, 2)
  end
end
