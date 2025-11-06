defmodule ExUtcp.Monitoring.HealthCheck do
  @moduledoc """
  Health check system for ExUtcp components.

  Monitors the health of transports, providers, and connections.
  """

  use GenServer

  require Logger

  @enforce_keys [:check_interval, :checks, :status]
  defstruct [:check_interval, :checks, :status, :last_check]

  @type health_status :: :healthy | :degraded | :unhealthy
  @type check_result :: %{
          name: String.t(),
          status: health_status(),
          message: String.t(),
          duration_ms: integer(),
          timestamp: integer()
        }

  @doc """
  Starts the health check system.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current health status.
  """
  @spec get_health_status() :: map()
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Forces a health check run.
  """
  @spec run_health_checks() :: map()
  def run_health_checks do
    GenServer.call(__MODULE__, :run_health_checks)
  end

  @doc """
  Registers a custom health check.
  """
  @spec register_check(String.t(), (-> check_result())) :: :ok
  def register_check(name, check_function) do
    GenServer.call(__MODULE__, {:register_check, name, check_function})
  end

  @doc """
  Unregisters a health check.
  """
  @spec unregister_check(String.t()) :: :ok
  def unregister_check(name) do
    GenServer.call(__MODULE__, {:unregister_check, name})
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    # 30 seconds
    check_interval = Keyword.get(opts, :check_interval, 30_000)

    # Register default health checks
    default_checks = %{
      "telemetry" => &check_telemetry/0,
      "prometheus" => &check_prometheus/0,
      "transports" => &check_transports/0,
      "memory" => &check_memory/0,
      "processes" => &check_processes/0
    }

    state = %__MODULE__{
      check_interval: check_interval,
      checks: default_checks,
      status: %{},
      last_check: nil
    }

    # Schedule first health check
    Process.send_after(self(), :run_health_checks, 1000)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_health_status, _from, state) do
    {:reply, build_health_response(state), state}
  end

  @impl GenServer
  def handle_call(:run_health_checks, _from, state) do
    {new_status, duration} = run_all_checks(state.checks)

    new_state = %{state | status: new_status, last_check: System.system_time(:millisecond)}

    # Emit telemetry event
    :telemetry.execute(
      [:ex_utcp, :health_check],
      %{duration: duration},
      %{overall_status: calculate_overall_status(new_status)}
    )

    response = build_health_response(new_state)
    {:reply, response, new_state}
  end

  @impl GenServer
  def handle_call({:register_check, name, check_function}, _from, state) do
    new_checks = Map.put(state.checks, name, check_function)
    new_state = %{state | checks: new_checks}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:unregister_check, name}, _from, state) do
    new_checks = Map.delete(state.checks, name)
    new_state = %{state | checks: new_checks}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:run_health_checks, state) do
    {new_status, _duration} = run_all_checks(state.checks)

    new_state = %{state | status: new_status, last_check: System.system_time(:millisecond)}

    # Schedule next health check
    Process.send_after(self(), :run_health_checks, state.check_interval)

    {:noreply, new_state}
  end

  # Private functions

  defp run_all_checks(checks) do
    start_time = System.monotonic_time(:millisecond)

    status =
      Enum.map(checks, fn {name, check_function} ->
        result = run_single_check(name, check_function)
        {name, result}
      end)
      |> Map.new()

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    {status, duration}
  end

  defp run_single_check(name, check_function) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = check_function.()
      end_time = System.monotonic_time(:millisecond)

      %{
        name: name,
        status: result.status,
        message: result.message,
        duration_ms: end_time - start_time,
        timestamp: System.system_time(:millisecond)
      }
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)

        %{
          name: name,
          status: :unhealthy,
          message: "Health check failed: #{inspect(error)}",
          duration_ms: end_time - start_time,
          timestamp: System.system_time(:millisecond)
        }
    end
  end

  defp build_health_response(state) do
    overall_status = calculate_overall_status(state.status)

    %{
      status: overall_status,
      checks: state.status,
      last_check: state.last_check,
      check_interval: state.check_interval,
      timestamp: System.system_time(:millisecond)
    }
  end

  defp calculate_overall_status(status) when map_size(status) == 0, do: :unknown

  defp calculate_overall_status(status) do
    statuses = Map.values(status) |> Enum.map(& &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      true -> :degraded
    end
  end

  # Default health check functions

  defp check_telemetry do
    # Test telemetry by emitting a test event
    :telemetry.execute([:ex_utcp, :health_check, :telemetry], %{}, %{})

    %{
      status: :healthy,
      message: "Telemetry system operational"
    }
  rescue
    error ->
      %{
        status: :unhealthy,
        message: "Telemetry system error: #{inspect(error)}"
      }
  end

  defp check_prometheus do
    # Check if PromEx is running
    case Process.whereis(ExUtcp.Monitoring.PromEx) do
      nil ->
        %{
          status: :degraded,
          message: "PromEx not running"
        }

      _pid ->
        %{
          status: :healthy,
          message: "Prometheus metrics operational"
        }
    end
  rescue
    error ->
      %{
        status: :unhealthy,
        message: "Prometheus system error: #{inspect(error)}"
      }
  end

  defp check_transports do
    transports = [
      {"http", ExUtcp.Transports.Http},
      {"cli", ExUtcp.Transports.Cli},
      {"websocket", ExUtcp.Transports.WebSocket},
      {"grpc", ExUtcp.Transports.Grpc},
      {"graphql", ExUtcp.Transports.Graphql},
      {"mcp", ExUtcp.Transports.Mcp},
      {"tcp_udp", ExUtcp.Transports.TcpUdp}
    ]

    transport_results =
      Enum.map(transports, fn {name, module} ->
        status =
          if Code.ensure_loaded?(module) and
               function_exported?(module, :transport_name, 0) do
            :healthy
          else
            :unhealthy
          end

        {name, status}
      end)

    healthy_count = Enum.count(transport_results, fn {_name, status} -> status == :healthy end)
    total_count = length(transport_results)

    overall_status =
      cond do
        healthy_count == total_count -> :healthy
        healthy_count > total_count / 2 -> :degraded
        true -> :unhealthy
      end

    %{
      status: overall_status,
      message: "#{healthy_count}/#{total_count} transports healthy"
    }
  end

  defp check_memory do
    memory_info = :erlang.memory()
    total_memory = memory_info[:total]

    # Check if memory usage is reasonable (less than 1GB for this example)
    # 1GB
    memory_limit = 1_000_000_000

    status =
      if total_memory < memory_limit do
        :healthy
      else
        :degraded
      end

    %{
      status: status,
      message: "Memory usage: #{Float.round(total_memory / 1_000_000, 2)} MB"
    }
  end

  defp check_processes do
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)

    usage_percentage = process_count / process_limit * 100

    status =
      cond do
        usage_percentage < 50 -> :healthy
        usage_percentage < 80 -> :degraded
        true -> :unhealthy
      end

    %{
      status: status,
      message: "Process usage: #{round(usage_percentage)}% (#{process_count}/#{process_limit})"
    }
  end
end
