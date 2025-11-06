defmodule ExUtcp.Monitoring.Metrics do
  @moduledoc """
  Metrics collection and aggregation for ExUtcp operations.

  Provides utilities for collecting, storing, and reporting metrics.
  """

  use GenServer

  require Logger

  @enforce_keys [:metrics, :config]
  defstruct [:metrics, :config, :start_time]

  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type metric_value :: number() | [number()]

  @doc """
  Starts the metrics collector.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increments a counter metric.
  """
  @spec increment_counter(String.t(), map()) :: :ok
  def increment_counter(metric_name, labels \\ %{}) do
    GenServer.cast(__MODULE__, {:increment_counter, metric_name, labels})
  end

  @doc """
  Sets a gauge metric value.
  """
  @spec set_gauge(String.t(), number(), map()) :: :ok
  def set_gauge(metric_name, value, labels \\ %{}) do
    GenServer.cast(__MODULE__, {:set_gauge, metric_name, value, labels})
  end

  @doc """
  Records a histogram observation.
  """
  @spec observe_histogram(String.t(), number(), map()) :: :ok
  def observe_histogram(metric_name, value, labels \\ %{}) do
    GenServer.cast(__MODULE__, {:observe_histogram, metric_name, value, labels})
  end

  @doc """
  Records a summary observation.
  """
  @spec observe_summary(String.t(), number(), map()) :: :ok
  def observe_summary(metric_name, value, labels \\ %{}) do
    GenServer.cast(__MODULE__, {:observe_summary, metric_name, value, labels})
  end

  @doc """
  Gets all collected metrics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets metrics for a specific metric name.
  """
  @spec get_metric(String.t()) :: map() | nil
  def get_metric(metric_name) do
    GenServer.call(__MODULE__, {:get_metric, metric_name})
  end

  @doc """
  Resets all metrics.
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  @doc """
  Gets metrics summary for reporting.
  """
  @spec get_metrics_summary() :: map()
  def get_metrics_summary do
    GenServer.call(__MODULE__, :get_metrics_summary)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    config = %{
      # 1 hour
      retention_period: Keyword.get(opts, :retention_period, 3600),
      max_metrics: Keyword.get(opts, :max_metrics, 1000),
      enable_cleanup: Keyword.get(opts, :enable_cleanup, true)
    }

    state = %__MODULE__{
      metrics: %{},
      config: config,
      start_time: System.system_time(:millisecond)
    }

    # Schedule periodic cleanup if enabled
    if config.enable_cleanup do
      Process.send_after(self(), :cleanup_metrics, config.retention_period * 1000)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:increment_counter, metric_name, labels}, state) do
    new_metrics = update_counter(state.metrics, metric_name, labels)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl GenServer
  def handle_cast({:set_gauge, metric_name, value, labels}, state) do
    new_metrics = update_gauge(state.metrics, metric_name, value, labels)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl GenServer
  def handle_cast({:observe_histogram, metric_name, value, labels}, state) do
    new_metrics = update_histogram(state.metrics, metric_name, value, labels)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl GenServer
  def handle_cast({:observe_summary, metric_name, value, labels}, state) do
    new_metrics = update_summary(state.metrics, metric_name, value, labels)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl GenServer
  def handle_call({:get_metric, metric_name}, _from, state) do
    metric = Map.get(state.metrics, metric_name)
    {:reply, metric, state}
  end

  @impl GenServer
  def handle_call(:reset_metrics, _from, state) do
    new_state = %{state | metrics: %{}}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_metrics_summary, _from, state) do
    summary = build_metrics_summary(state)
    {:reply, summary, state}
  end

  @impl GenServer
  def handle_info(:cleanup_metrics, state) do
    new_metrics = cleanup_old_metrics(state.metrics, state.config.retention_period)
    new_state = %{state | metrics: new_metrics}

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_metrics, state.config.retention_period * 1000)

    {:noreply, new_state}
  end

  # Private functions

  defp update_counter(metrics, metric_name, labels) do
    key = build_metric_key(metric_name, labels)
    current_value = get_in(metrics, [metric_name, key, :value]) || 0

    # Ensure the metric_name key exists in the metrics map
    metrics = Map.put_new(metrics, metric_name, %{})

    put_in(metrics, [metric_name, key], %{
      type: :counter,
      value: current_value + 1,
      labels: labels,
      timestamp: System.system_time(:millisecond)
    })
  end

  defp update_gauge(metrics, metric_name, value, labels) do
    key = build_metric_key(metric_name, labels)

    # Ensure the metric_name key exists in the metrics map
    metrics = Map.put_new(metrics, metric_name, %{})

    put_in(metrics, [metric_name, key], %{
      type: :gauge,
      value: value,
      labels: labels,
      timestamp: System.system_time(:millisecond)
    })
  end

  defp update_histogram(metrics, metric_name, value, labels) do
    key = build_metric_key(metric_name, labels)
    current_values = get_in(metrics, [metric_name, key, :values]) || []

    # Ensure the metric_name key exists in the metrics map
    metrics = Map.put_new(metrics, metric_name, %{})

    put_in(metrics, [metric_name, key], %{
      type: :histogram,
      # Keep last 1000 values
      values: [value | current_values] |> Enum.take(1000),
      labels: labels,
      timestamp: System.system_time(:millisecond)
    })
  end

  defp update_summary(metrics, metric_name, value, labels) do
    key = build_metric_key(metric_name, labels)
    current_values = get_in(metrics, [metric_name, key, :values]) || []

    # Ensure the metric_name key exists in the metrics map
    metrics = Map.put_new(metrics, metric_name, %{})

    put_in(metrics, [metric_name, key], %{
      type: :summary,
      # Keep last 1000 values
      values: [value | current_values] |> Enum.take(1000),
      labels: labels,
      timestamp: System.system_time(:millisecond)
    })
  end

  defp build_metric_key(metric_name, labels) do
    labels_string =
      labels
      |> Enum.sort()
      |> Enum.map_join(",", fn {k, v} -> "#{k}=#{v}" end)

    "#{metric_name}[#{labels_string}]"
  end

  defp cleanup_old_metrics(metrics, retention_period_seconds) do
    cutoff_time = System.system_time(:millisecond) - retention_period_seconds * 1000

    Enum.map(metrics, fn {metric_name, metric_data} ->
      cleaned_data =
        Enum.filter(metric_data, fn {_key, data} ->
          data.timestamp > cutoff_time
        end)
        |> Map.new()

      {metric_name, cleaned_data}
    end)
    |> Map.new()
  end

  defp build_metrics_summary(state) do
    uptime = System.system_time(:millisecond) - state.start_time

    %{
      uptime_ms: uptime,
      total_metrics: map_size(state.metrics),
      config: state.config,
      memory_usage: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count)
    }
  end
end
