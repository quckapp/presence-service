defmodule PresenceService.Actors.UserSession do
  @moduledoc """
  User Session Actor - Manages individual user's presence state using GenServer.
  Each connected user has their own supervised process.
  """
  use GenServer, restart: :transient
  require Logger

  @heartbeat_interval 30_000
  @idle_timeout 300_000  # 5 minutes for auto-away

  defstruct [:user_id, :status, :last_activity, :metadata, :socket_pid, :device_info]

  # Client API

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(user_id))
  end

  def via_tuple(user_id) do
    {:via, Horde.Registry, {PresenceService.PresenceRegistry, user_id}}
  end

  def get_state(user_id) do
    GenServer.call(via_tuple(user_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def update_status(user_id, status) do
    GenServer.cast(via_tuple(user_id), {:update_status, status})
  end

  def record_activity(user_id) do
    GenServer.cast(via_tuple(user_id), :record_activity)
  end

  def disconnect(user_id) do
    GenServer.cast(via_tuple(user_id), :disconnect)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    socket_pid = Keyword.get(opts, :socket_pid)
    metadata = Keyword.get(opts, :metadata, %{})

    if socket_pid do
      Process.monitor(socket_pid)
    end

    state = %__MODULE__{
      user_id: user_id,
      status: :online,
      last_activity: DateTime.utc_now(),
      metadata: metadata,
      socket_pid: socket_pid,
      device_info: Map.get(metadata, :device_info, %{})
    }

    # Register presence
    PresenceService.PresenceManager.set_presence(user_id, :online, metadata)

    # Schedule heartbeat
    schedule_heartbeat()
    schedule_idle_check()

    Logger.info("User session started for #{user_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_cast({:update_status, status}, state) do
    PresenceService.PresenceManager.set_presence(state.user_id, status, state.metadata)
    {:noreply, %{state | status: status, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast(:record_activity, state) do
    new_state = %{state | last_activity: DateTime.utc_now()}
    
    # If user was away, set them back to online
    if state.status == :away do
      PresenceService.PresenceManager.set_presence(state.user_id, :online, state.metadata)
      {:noreply, %{new_state | status: :online}}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast(:disconnect, state) do
    PresenceService.PresenceManager.set_presence(state.user_id, :offline, %{reason: "disconnected"})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    PresenceService.PresenceManager.heartbeat(state.user_id)
    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_idle, state) do
    now = DateTime.utc_now()
    idle_ms = DateTime.diff(now, state.last_activity, :millisecond)

    new_state = if idle_ms > @idle_timeout and state.status == :online do
      PresenceService.PresenceManager.set_presence(state.user_id, :away, Map.put(state.metadata, :reason, "idle"))
      %{state | status: :away}
    else
      state
    end

    schedule_idle_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{socket_pid: pid} = state) do
    Logger.info("Socket disconnected for user #{state.user_id}")
    PresenceService.PresenceManager.set_presence(state.user_id, :offline, %{reason: "socket_closed"})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("User session terminated for #{state.user_id}")
    :ok
  end

  # Private Functions

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  defp schedule_idle_check do
    Process.send_after(self(), :check_idle, 60_000)
  end
end
