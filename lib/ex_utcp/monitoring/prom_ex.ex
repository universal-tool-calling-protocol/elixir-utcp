defmodule ExUtcp.Monitoring.PromEx do
  @moduledoc """
  PromEx configuration for ExUtcp metrics.

  Defines Prometheus metrics for monitoring UTCP operations.
  """

  use PromEx, otp_app: :ex_utcp

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # Built-in PromEx plugins
      Plugins.Application,
      Plugins.Beam,

      # Custom ExUtcp plugin
      {ExUtcp.Monitoring.PromEx.Plugin, []}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # Custom ExUtcp dashboard
      {:prom_ex, "ex_utcp.json"}
    ]
  end
end

defmodule ExUtcp.Monitoring.PromEx.Plugin do
  @moduledoc """
  Custom PromEx plugin for ExUtcp-specific metrics.
  """

  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      # System metrics polling
      {
        [:ex_utcp, :system],
        [
          # Memory usage metrics
          last_value("ex_utcp.system.memory.total.bytes",
            event_name: [:ex_utcp, :system, :memory],
            measurement: :total,
            description: "Total memory usage",
            unit: :byte
          ),
          last_value("ex_utcp.system.memory.processes.bytes",
            event_name: [:ex_utcp, :system, :memory],
            measurement: :processes,
            description: "Process memory usage",
            unit: :byte
          ),

          # Process count metrics
          last_value("ex_utcp.system.processes.count",
            event_name: [:ex_utcp, :system, :processes],
            measurement: :count,
            description: "Number of processes"
          )
        ],
        poll_rate
      }
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      # Tool call metrics
      counter(
        "ex_utcp.tool_calls.total",
        event_name: [:ex_utcp, :tool_call],
        description: "Total number of tool calls",
        tags: [:tool_name, :provider_name, :status]
      ),
      distribution(
        "ex_utcp.tool_call.duration.milliseconds",
        event_name: [:ex_utcp, :tool_call],
        measurement: :duration,
        description: "Tool call duration",
        tags: [:tool_name, :provider_name],
        unit: :millisecond,
        buckets: [10, 50, 100, 500, 1000, 5000, 10_000]
      ),

      # Search metrics
      counter(
        "ex_utcp.searches.total",
        event_name: [:ex_utcp, :search],
        description: "Total number of searches",
        tags: [:algorithm]
      ),
      distribution(
        "ex_utcp.search.duration.milliseconds",
        event_name: [:ex_utcp, :search],
        measurement: :duration,
        description: "Search duration",
        tags: [:algorithm],
        unit: :millisecond,
        buckets: [1, 5, 10, 50, 100, 500, 1000]
      ),
      distribution(
        "ex_utcp.search.results.count",
        event_name: [:ex_utcp, :search],
        measurement: :result_count,
        description: "Number of search results",
        tags: [:algorithm],
        buckets: [0, 1, 5, 10, 20, 50, 100]
      ),

      # Provider metrics
      counter(
        "ex_utcp.providers.total",
        event_name: [:ex_utcp, :provider],
        description: "Total provider operations",
        tags: [:transport_type, :action]
      ),

      # Connection metrics
      counter(
        "ex_utcp.connections.total",
        event_name: [:ex_utcp, :connection],
        description: "Total connection events",
        tags: [:transport_type, :event]
      ),
      distribution(
        "ex_utcp.connection.duration.milliseconds",
        event_name: [:ex_utcp, :connection],
        measurement: :duration,
        description: "Connection establishment duration",
        tags: [:transport_type],
        unit: :millisecond,
        buckets: [10, 50, 100, 500, 1000, 5000]
      )
    ]
  end

  @impl true
  def manual_metrics(_opts) do
    [
      # Manual metrics that can be updated programmatically
      last_value(
        "ex_utcp.active_connections.count",
        description: "Number of active connections"
      ),
      last_value(
        "ex_utcp.registered_tools.count",
        description: "Number of registered tools"
      ),
      last_value(
        "ex_utcp.registered_providers.count",
        description: "Number of registered providers"
      )
    ]
  end
end
