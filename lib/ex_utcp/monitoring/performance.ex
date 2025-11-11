defmodule ExUtcp.Monitoring.Performance do
  @moduledoc """
  Performance monitoring for ExUtcp operations.

  Tracks performance metrics, identifies bottlenecks, and provides alerts.
  """

  use GenServer

  alias ExUtcp.Monitoring.Metrics

  require Logger

  @enforce_keys [:config, :start_time]
  defstruct [:config, :start_time, :metrics]

  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type metric_value :: number() | [number()]

  @doc """
  Starts the performance monitor.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Measures the execution time of a function and emits telemetry.
  """
  @spec measure(String.t(), map(), (-> any())) :: any()
  def measure(operation_name, metadata \\ %{}, fun) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Emit telemetry event
      :telemetry.execute(
        [:ex_utcp, :performance, :operation],
        %{duration: duration},
        Map.merge(metadata, %{operation: operation_name, status: :success})
      )

      # Record metrics
      Metrics.observe_histogram("operation_duration_ms", duration, %{
        operation: operation_name,
        status: "success"
      })

      result
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        # Emit telemetry event for error
        :telemetry.execute(
          [:ex_utcp, :performance, :operation],
          %{duration: duration},
          Map.merge(metadata, %{operation: operation_name, status: :error, error: inspect(error)})
        )

        # Record error metrics
        Metrics.observe_histogram("operation_duration_ms", duration, %{
          operation: operation_name,
          status: "error"
        })

        Metrics.increment_counter("operation_errors_total", %{
          operation: operation_name,
          error_type: error.__struct__ |> to_string()
        })

        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Measures tool call performance.
  """
  @spec measure_tool_call(String.t(), String.t(), map(), (-> any())) :: any()
  def measure_tool_call(tool_name, provider_name, args, fun) do
    metadata = %{
      tool_name: tool_name,
      provider_name: provider_name,
      args_count: map_size(args)
    }

    measure("tool_call", metadata, fun)
  end

  @doc """
  Measures search performance.
  """
  @spec measure_search(String.t(), atom(), map(), (-> any())) :: any()
  def measure_search(query, algorithm, filters, fun) do
    metadata = %{
      query_length: String.length(query),
      algorithm: algorithm,
      filter_count: count_active_filters(filters)
    }

    result = measure("search", metadata, fun)

    # Additional search-specific metrics
    if is_list(result) do
      Metrics.observe_histogram("search_results_count", length(result), %{
        algorithm: algorithm
      })
    end

    result
  end

  @doc """
  Measures connection performance.
  """
  @spec measure_connection(String.t(), atom(), (-> any())) :: any()
  def measure_connection(provider_name, transport_type, fun) do
    metadata = %{
      provider_name: provider_name,
      transport_type: transport_type
    }

    measure("connection", metadata, fun)
  end

  @doc """
  Gets performance statistics for a specific operation.
  """
  @spec get_operation_stats(String.t()) :: map()
  def get_operation_stats(operation_name) do
    histogram_data = Metrics.get_metric("operation_duration_ms")

    case histogram_data do
      nil ->
        %{operation: operation_name, stats: :no_data}

      data ->
        # Calculate statistics from histogram data
        operation_data =
          data
          |> Enum.filter(fn {_key, metric} ->
            metric.labels[:operation] == operation_name
          end)

        if Enum.empty?(operation_data) do
          %{operation: operation_name, stats: :no_data}
        else
          values =
            Enum.flat_map(operation_data, fn {_key, metric} ->
              metric.values || [metric.value]
            end)

          %{
            operation: operation_name,
            stats: calculate_statistics(values)
          }
        end
    end
  rescue
    _ -> %{operation: operation_name, stats: :unavailable}
  end

  @doc """
  Gets performance summary for all operations.
  """
  @spec get_performance_summary() :: map()
  def get_performance_summary do
    metrics = Metrics.get_metrics()

    %{
      operations: get_all_operation_stats(metrics),
      system: get_system_performance(),
      alerts: get_performance_alerts(metrics),
      timestamp: System.system_time(:millisecond)
    }
  rescue
    _ ->
      %{
        operations: %{},
        system: get_system_performance(),
        alerts: [],
        timestamp: System.system_time(:millisecond),
        status: :metrics_unavailable
      }
  end

  @doc """
  Checks for performance alerts based on thresholds.
  """
  @spec get_performance_alerts(map()) :: [map()]
  def get_performance_alerts(metrics \\ nil) do
    metrics = metrics || Metrics.get_metrics()
    alerts = []

    # Check for slow operations
    alerts = alerts ++ check_slow_operations(metrics)

    # Check for high error rates
    alerts = alerts ++ check_error_rates(metrics)

    # Check for memory usage
    alerts = alerts ++ check_memory_alerts()

    alerts
  rescue
    _ -> []
  end

  @doc """
  Records a custom performance metric.
  """
  @spec record_custom_metric(String.t(), metric_type(), metric_value(), map()) :: :ok
  def record_custom_metric(name, type, value, labels \\ %{}) do
    case type do
      :counter -> Metrics.increment_counter(name, labels)
      :gauge -> Metrics.set_gauge(name, value, labels)
      :histogram -> Metrics.observe_histogram(name, value, labels)
      :summary -> Metrics.observe_summary(name, value, labels)
    end
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    config = %{
      alert_thresholds: %{
        slow_operation_ms: Keyword.get(opts, :slow_operation_threshold, 5000),
        high_error_rate: Keyword.get(opts, :high_error_rate, 0.1),
        high_memory_mb: Keyword.get(opts, :high_memory_threshold, 500)
      },
      # 5 minutes
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 300_000)
    }

    state = %__MODULE__{
      config: config,
      start_time: System.system_time(:millisecond),
      metrics: %{}
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_old_data, config.cleanup_interval)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:increment_counter, metric_name, labels}, state) do
    :ok = Metrics.increment_counter(metric_name, labels)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_gauge, metric_name, value, labels}, state) do
    :ok = Metrics.set_gauge(metric_name, value, labels)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:observe_histogram, metric_name, value, labels}, state) do
    :ok = Metrics.observe_histogram(metric_name, value, labels)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:observe_summary, metric_name, value, labels}, state) do
    :ok = Metrics.observe_summary(metric_name, value, labels)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    metrics = Metrics.get_metrics()
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:get_metric, metric_name}, _from, state) do
    metric = Metrics.get_metric(metric_name)
    {:reply, metric, state}
  end

  @impl GenServer
  def handle_call(:reset_metrics, _from, state) do
    :ok = Metrics.reset_metrics()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_metrics_summary, _from, state) do
    summary = get_performance_summary()
    {:reply, summary, state}
  end

  @impl GenServer
  def handle_info(:cleanup_old_data, state) do
    # Perform cleanup operations
    Logger.debug("Performing metrics cleanup")

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_data, state.config.cleanup_interval)

    {:noreply, state}
  end

  # Private helper functions

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

  defp calculate_statistics([]), do: %{count: 0}

  defp calculate_statistics(values) do
    sorted_values = Enum.sort(values)
    count = length(values)
    sum = Enum.sum(values)

    %{
      count: count,
      sum: sum,
      min: Enum.min(values),
      max: Enum.max(values),
      mean: sum / count,
      median: calculate_median(sorted_values),
      p95: calculate_percentile(sorted_values, 0.95),
      p99: calculate_percentile(sorted_values, 0.99)
    }
  end

  defp calculate_median(sorted_values) do
    count = length(sorted_values)

    if rem(count, 2) == 0 do
      mid1 = Enum.at(sorted_values, div(count, 2) - 1)
      mid2 = Enum.at(sorted_values, div(count, 2))
      (mid1 + mid2) / 2
    else
      Enum.at(sorted_values, div(count, 2))
    end
  end

  defp calculate_percentile(sorted_values, percentile) do
    count = length(sorted_values)
    index = round(count * percentile) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_values, index)
  end

  defp get_all_operation_stats(_metrics) do
    # Extract operation statistics from metrics
    %{
      tool_calls: get_operation_stats("tool_call"),
      searches: get_operation_stats("search"),
      connections: get_operation_stats("connection")
    }
  end

  defp get_system_performance do
    memory = :erlang.memory()

    %{
      memory_mb: Float.round(memory[:total] / 1_000_000, 2),
      process_count: :erlang.system_info(:process_count),
      scheduler_utilization: get_scheduler_utilization(),
      garbage_collection: get_gc_stats()
    }
  end

  defp get_scheduler_utilization do
    # Get scheduler utilization (simplified)
    schedulers = :erlang.system_info(:schedulers_online)

    %{
      schedulers_online: schedulers,
      # Would require more complex calculation
      utilization: "N/A"
    }
  end

  defp get_gc_stats do
    # Get garbage collection statistics
    {gc_count, gc_words_reclaimed, _} = :erlang.statistics(:garbage_collection)

    %{
      collections: gc_count,
      words_reclaimed: gc_words_reclaimed
    }
  end

  defp check_slow_operations(_metrics) do
    # Check for operations that exceed threshold
    # This would analyze histogram data for slow operations
    []
  end

  defp check_error_rates(_metrics) do
    # Check for high error rates
    # This would analyze counter data for error rates
    []
  end

  defp check_memory_alerts do
    memory = :erlang.memory(:total)
    memory_mb = memory / 1_000_000

    if memory_mb > 500 do
      [
        %{
          type: :memory,
          severity: :warning,
          message: "High memory usage: #{Float.round(memory_mb, 2)} MB",
          timestamp: System.system_time(:millisecond)
        }
      ]
    else
      []
    end
  end
end
