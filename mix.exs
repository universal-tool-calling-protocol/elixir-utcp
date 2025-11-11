defmodule ExUtcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_utcp,
      version: "0.3.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/universal-tool-calling-protocol/elixir-utcp",
      docs: [
        main: "ExUtcp",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # WebSocket support
      {:websockex, "~> 0.4"},

      # gRPC support
      {:grpc, "~> 0.11"},
      {:protobuf, "~> 0.15"},

      # GraphQL support
      {:absinthe, "~> 1.8"},
      {:absinthe_plug, "~> 1.5"},

      # Environment variables
      {:dotenvy, "~> 1.1"},

      # YAML support for OpenAPI
      {:yaml_elixir, "~> 2.12"},

      # Search libraries
      {:fuzzy_compare, "~> 1.1"},
      {:truffle_hog, "~> 0.1"},
      {:haystack, "~> 0.1"},

      # Monitoring and metrics
      {:telemetry, "~> 1.3"},
      {:prom_ex, "~> 1.11"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},

      # WebRTC support
      {:ex_webrtc, "~> 0.15"},

      # Testing
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir implementation of the Universal Tool Calling Protocol (UTCP)"
  end

  defp package do
    [
      maintainers: ["Thanos Vassilakis"],
      licenses: ["MPL-2.0"],
      links: %{
        "GitHub" => "https://github.com/universal-tool-calling-protocol/elixir-utcp",
        "Documentation" => "https://hexdocs.pm/ex_utcp"
      }
    ]
  end
end
