defmodule VsmEventBus.MixProject do
  use Mix.Project

  def project do
    [
      app: :vsm_event_bus,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Package metadata
      description: "VSM Event Bus - Centralized event coordination for Viable System Model implementations",
      package: package(),
      docs: [
        main: "VsmEventBus",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      
      # Test configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {VsmEventBus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies for VSM event coordination
      {:phoenix_pubsub, "~> 2.1"},
      {:libcluster, "~> 3.3"},
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:jason, "~> 1.4"},
      {:uuid, "~> 1.1"},
      
      # VSM Core integration (when published)
      # {:vsm_core, "~> 0.1", path: "../vsm-core"},
      
      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 0.6", only: :test}
    ]
  end
  
  defp package do
    [
      maintainers: ["VSM Core Team"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/viable-systems/vsm-event-bus",
        "VSM Docs" => "https://viable-systems.github.io/vsm-docs/"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end