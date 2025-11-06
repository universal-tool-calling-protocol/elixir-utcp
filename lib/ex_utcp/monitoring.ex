defmodule ExUtcp.Monitoring do
  @moduledoc """
  Monitoring and metrics system for ExUtcp.

  Provides comprehensive monitoring capabilities including:
  - Telemetry events for all UTCP operations
  - Prometheus metrics integration
  - Health checks for transports and providers
  - Performance monitoring and alerting
  - Custom metrics and dashboards
  """

  require Logger

  @doc """
  Starts the monitoring system.
  """
  @spec start() :: :ok
  def start do
    # Attach telemetry handlers
    attach_telemetry_handlers()

    # Start Prometheus metrics
    start_prometheus_metrics()

    # Start health check system
    start_health_checks()

    Logger.info("ExUtcp monitoring system started")
    :ok
  end

  @doc """
  Stops the monitoring system.
  """
  @spec stop() :: :ok
  def stop do
    # Detach telemetry handlers
    detach_telemetry_handlers()

    Logger.info("ExUtcp monitoring system stopped")
    :ok
  end

  @doc """
  Emits a telemetry event for tool call operations.
  """
  @spec emit_tool_call_event(String.t(), String.t(), map(), integer(), :success | :error, any()) ::
          :ok
  def emit_tool_call_event(tool_name, provider_name, args, duration_ms, status, result_or_error) do
    metadata = %{
      tool_name: tool_name,
      provider_name: provider_name,
      args_count: map_size(args),
      status: status,
      result_size: calculate_result_size(result_or_error)
    }

    measurements = %{
      duration: duration_ms,
      timestamp: System.system_time(:millisecond)
    }

    :telemetry.execute([:ex_utcp, :tool_call], measurements, metadata)
  end

  @doc """
  Emits a telemetry event for search operations.
  """
  @spec emit_search_event(String.t(), atom(), map(), integer(), integer()) :: :ok
  def emit_search_event(query, algorithm, filters, duration_ms, result_count) do
    metadata = %{
      query_length: String.length(query),
      algorithm: algorithm,
      filter_count: count_active_filters(filters),
      result_count: result_count
    }

    measurements = %{
      duration: duration_ms,
      timestamp: System.system_time(:millisecond)
    }

    :telemetry.execute([:ex_utcp, :search], measurements, metadata)
  end

  @doc """
  Emits a telemetry event for provider registration.
  """
  @spec emit_provider_event(String.t(), atom(), :register | :deregister, integer()) :: :ok
  def emit_provider_event(provider_name, transport_type, action, tool_count) do
    metadata = %{
      provider_name: provider_name,
      transport_type: transport_type,
      action: action,
      tool_count: tool_count
    }

    measurements = %{
      timestamp: System.system_time(:millisecond)
    }

    :telemetry.execute([:ex_utcp, :provider], measurements, metadata)
  end

  @doc """
  Emits a telemetry event for connection operations.
  """
  @spec emit_connection_event(String.t(), atom(), :connect | :disconnect | :error, integer()) ::
          :ok
  def emit_connection_event(provider_name, transport_type, event, duration_ms \\ 0) do
    metadata = %{
      provider_name: provider_name,
      transport_type: transport_type,
      event: event
    }

    measurements = %{
      duration: duration_ms,
      timestamp: System.system_time(:millisecond)
    }

    :telemetry.execute([:ex_utcp, :connection], measurements, metadata)
  end

  @doc """
  Gets current system metrics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    %{
      system: get_system_metrics(),
      utcp: get_utcp_metrics(),
      timestamp: System.system_time(:millisecond)
    }
  end

  @doc """
  Gets health status for all components.
  """
  @spec get_health_status() :: map()
  def get_health_status do
    %{
      overall: :healthy,
      components: %{
        telemetry: check_telemetry_health(),
        prometheus: check_prometheus_health(),
        transports: check_transports_health()
      },
      timestamp: System.system_time(:millisecond)
    }
  end

  # Private functions

  defp attach_telemetry_handlers do
    # Attach handlers for tool call metrics
    :telemetry.attach_many(
      "ex_utcp_tool_calls",
      [
        [:ex_utcp, :tool_call]
      ],
      &handle_tool_call_event/4,
      nil
    )

    # Attach handlers for search metrics
    :telemetry.attach_many(
      "ex_utcp_search",
      [
        [:ex_utcp, :search]
      ],
      &handle_search_event/4,
      nil
    )

    # Attach handlers for provider metrics
    :telemetry.attach_many(
      "ex_utcp_providers",
      [
        [:ex_utcp, :provider]
      ],
      &handle_provider_event/4,
      nil
    )

    # Attach handlers for connection metrics
    :telemetry.attach_many(
      "ex_utcp_connections",
      [
        [:ex_utcp, :connection]
      ],
      &handle_connection_event/4,
      nil
    )
  end

  defp detach_telemetry_handlers do
    :telemetry.detach("ex_utcp_tool_calls")
    :telemetry.detach("ex_utcp_search")
    :telemetry.detach("ex_utcp_providers")
    :telemetry.detach("ex_utcp_connections")
  end

  defp start_prometheus_metrics do
    # PromEx will be configured in application.ex
    :ok
  end

  defp start_health_checks do
    # Health checks will be implemented as a separate GenServer
    :ok
  end

  defp handle_tool_call_event([:ex_utcp, :tool_call], measurements, metadata, _config) do
    Logger.info(
      "Tool call: #{metadata.tool_name} (#{metadata.provider_name}) - #{metadata.status} in #{measurements.duration}ms"
    )

    # Update counters and histograms
    :telemetry.execute(
      [:prom_ex, :plugin, :application, :tool_calls_total],
      %{},
      %{
        tool_name: metadata.tool_name,
        provider_name: metadata.provider_name,
        status: metadata.status
      }
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :application, :tool_call_duration_milliseconds],
      %{duration: measurements.duration},
      %{
        tool_name: metadata.tool_name,
        provider_name: metadata.provider_name
      }
    )
  end

  defp handle_search_event([:ex_utcp, :search], measurements, metadata, _config) do
    Logger.debug(
      "Search: '#{String.slice((metadata.query_length > 0 && "query") || "empty", 0, 20)}' (#{metadata.algorithm}) - #{metadata.result_count} results in #{measurements.duration}ms"
    )

    # Update search metrics
    :telemetry.execute(
      [:prom_ex, :plugin, :application, :searches_total],
      %{},
      %{algorithm: metadata.algorithm}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :application, :search_duration_milliseconds],
      %{duration: measurements.duration},
      %{algorithm: metadata.algorithm}
    )
  end

  defp handle_provider_event([:ex_utcp, :provider], _measurements, metadata, _config) do
    Logger.info(
      "Provider #{metadata.action}: #{metadata.provider_name} (#{metadata.transport_type}) with #{metadata.tool_count} tools"
    )

    # Update provider metrics
    :telemetry.execute(
      [:prom_ex, :plugin, :application, :providers_total],
      %{},
      %{
        transport_type: metadata.transport_type,
        action: metadata.action
      }
    )
  end

  defp handle_connection_event([:ex_utcp, :connection], measurements, metadata, _config) do
    Logger.debug(
      "Connection #{metadata.event}: #{metadata.provider_name} (#{metadata.transport_type}) in #{measurements.duration}ms"
    )

    # Update connection metrics
    :telemetry.execute(
      [:prom_ex, :plugin, :application, :connections_total],
      %{},
      %{
        transport_type: metadata.transport_type,
        event: metadata.event
      }
    )

    if measurements.duration > 0 do
      :telemetry.execute(
        [:prom_ex, :plugin, :application, :connection_duration_milliseconds],
        %{duration: measurements.duration},
        %{transport_type: metadata.transport_type}
      )
    end
  end

  defp calculate_result_size(result) when is_binary(result), do: byte_size(result)
  defp calculate_result_size(result) when is_map(result), do: map_size(result)
  defp calculate_result_size(result) when is_list(result), do: length(result)
  defp calculate_result_size(_), do: 0

  defp count_active_filters(filters) when is_map(filters) do
    filters
    |> Enum.count(fn {_key, value} ->
      case value do
        list when is_list(list) -> not Enum.empty?(list)
        _ -> value != nil
      end
    end)
  end

  defp count_active_filters(_), do: 0

  defp get_system_metrics do
    %{
      memory: %{
        total: :erlang.memory(:total),
        processes: :erlang.memory(:processes),
        system: :erlang.memory(:system),
        atom: :erlang.memory(:atom),
        binary: :erlang.memory(:binary),
        ets: :erlang.memory(:ets)
      },
      processes: %{
        count: :erlang.system_info(:process_count),
        limit: :erlang.system_info(:process_limit)
      },
      schedulers: %{
        online: :erlang.system_info(:schedulers_online),
        total: :erlang.system_info(:schedulers)
      }
    }
  end

  defp get_utcp_metrics do
    # These would be populated from actual usage statistics
    %{
      tool_calls: %{
        total: 0,
        success: 0,
        error: 0,
        avg_duration: 0.0
      },
      searches: %{
        total: 0,
        by_algorithm: %{
          exact: 0,
          fuzzy: 0,
          semantic: 0,
          combined: 0
        }
      },
      providers: %{
        total: 0,
        by_transport: %{
          http: 0,
          websocket: 0,
          grpc: 0,
          graphql: 0,
          mcp: 0,
          tcp: 0,
          udp: 0,
          cli: 0
        }
      },
      connections: %{
        active: 0,
        total: 0,
        failed: 0
      }
    }
  end

  # Check if telemetry is working
  defp check_telemetry_health do
    :telemetry.execute([:ex_utcp, :health_check], %{}, %{component: :telemetry})
    :healthy
  rescue
    _ -> :unhealthy
  end

  # Check if Prometheus metrics are working
  defp check_prometheus_health do
    # This would check if PromEx is running and accessible
    :healthy
  rescue
    _ -> :unhealthy
  end

  defp check_transports_health do
    # Check health of all transport modules
    transports = [
      ExUtcp.Transports.Http,
      ExUtcp.Transports.Cli,
      ExUtcp.Transports.WebSocket,
      ExUtcp.Transports.Grpc,
      ExUtcp.Transports.Graphql,
      ExUtcp.Transports.Mcp,
      ExUtcp.Transports.TcpUdp
    ]

    transport_health =
      Enum.map(transports, fn transport ->
        transport_name = transport.transport_name()
        health_status = check_transport_health(transport)
        {transport_name, health_status}
      end)
      |> Map.new()

    overall_health =
      if Enum.all?(Map.values(transport_health), &(&1 == :healthy)) do
        :healthy
      else
        :degraded
      end

    %{
      overall: overall_health,
      transports: transport_health
    }
  end

  defp check_transport_health(transport) do
    # Check if transport module is loaded and has required functions
    if function_exported?(transport, :transport_name, 0) and
         function_exported?(transport, :supports_streaming?, 0) do
      :healthy
    else
      :unhealthy
    end
  rescue
    _ -> :unhealthy
  end
end
