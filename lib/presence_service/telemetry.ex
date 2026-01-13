defmodule PresenceService.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [{Telemetry.Metrics.ConsoleReporter, metrics: metrics()}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("presence.user.connected.count"),
      counter("presence.user.disconnected.count"),
      summary("presence.status.update.duration", unit: {:native, :millisecond}),
      last_value("presence.users.online.count"),
      counter("presence.heartbeat.count"),
      summary("presence.mongo.query.duration", unit: {:native, :millisecond})
    ]
  end
end
