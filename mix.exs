defmodule PresenceService.MixProject do
  use Mix.Project

  def project do
    [
      app: :presence_service,
      version: "1.0.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [
        presence_service: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {PresenceService.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:cors_plug, "~> 3.0"},
      {:mongodb_driver, "~> 1.4"},
      {:redix, "~> 1.3"},
      {:phoenix_pubsub_redis, "~> 3.0"},
      {:brod, "~> 3.16"},
      {:guardian, "~> 2.3"},
      {:finch, "~> 0.18"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:libcluster, "~> 3.3"},
      {:horde, "~> 0.9"},
      {:timex, "~> 3.7"},
      {:uuid, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [setup: ["deps.get"], test: ["test"]]
  end
end
