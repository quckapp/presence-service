defmodule PresenceService.PresenceCleanup do
  use GenServer
  require Logger

  alias PresenceService.Repo

  @cleanup_interval 30_000  # 30 seconds
  @stale_threshold 120  # 2 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_stale_presence()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_stale_presence do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_threshold, :second)

    case Repo.cleanup_stale_presence(threshold) do
      {:ok, result} ->
        if result.modified_count > 0 do
          Logger.info("Cleaned up #{result.modified_count} stale presence records")
        end
      {:error, reason} ->
        Logger.error("Failed to cleanup stale presence: #{inspect(reason)}")
    end
  end
end
