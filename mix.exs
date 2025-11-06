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
      source_url: "https://github.com/thanos/ex_utcp",
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
      {:req, "~> 0.4"},
      {:jason, "~> 1.4"},

      # WebSocket support
      {:websockex, "~> 0.4"},

      # gRPC support
      {:grpc, "~> 0.7"},
      {:protobuf, "~> 0.12"},

      # GraphQL support
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},

      # Environment variables
      {:dotenvy, "~> 0.8"},

      # YAML support for OpenAPI
      {:yaml_elixir, "~> 2.9"},

      # Search libraries
      {:fuzzy_compare, "~> 1.1"},
      {:truffle_hog, "~> 0.1"},
      {:haystack, "~> 0.1"},

      # Monitoring and metrics
      {:telemetry, "~> 1.2"},
      {:prom_ex, "~> 1.9"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},

      # WebRTC support
      {:ex_webrtc, "~> 0.15"},

      # Testing
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
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
        "GitHub" => "https://github.com/thanos/ex_utcp",
        "Documentation" => "https://hexdocs.pm/ex_utcp"
      }
    ]
  end
end
