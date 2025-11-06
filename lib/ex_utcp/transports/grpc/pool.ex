defmodule ExUtcp.Transports.Grpc.Pool do
  @moduledoc """
  Manages a pool of gRPC connections with lifecycle management.
  """

  use GenServer

  alias ExUtcp.Transports.Grpc.Connection

  require Logger

  defstruct [
    :connections,
    :max_connections,
    :connection_timeout,
    :cleanup_interval,
    :max_idle_time
  ]

  @type t :: %__MODULE__{
          connections: %{String.t() => pid()},
          max_connections: non_neg_integer(),
          connection_timeout: timeout(),
          cleanup_interval: timeout(),
          max_idle_time: timeout()
        }

  @doc """
  Starts the connection pool.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets or creates a connection for the given provider.
  """
  @spec get_connection(map()) :: {:ok, pid()} | {:error, term()}
  def get_connection(provider) do
    GenServer.call(__MODULE__, {:get_connection, provider})
  end

  @doc """
  Returns a connection to the pool.
  """
  @spec return_connection(pid()) :: :ok
  def return_connection(pid) do
    GenServer.cast(__MODULE__, {:return_connection, pid})
  end

  @doc """
  Closes a specific connection.
  """
  @spec close_connection(pid()) :: :ok
  def close_connection(pid) do
    GenServer.cast(__MODULE__, {:close_connection, pid})
  end

  @doc """
  Closes all connections.
  """
  @spec close_all_connections() :: :ok
  def close_all_connections do
    GenServer.cast(__MODULE__, :close_all_connections)
  end

  @doc """
  Gets pool statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      connections: %{},
      max_connections: Keyword.get(opts, :max_connections, 10),
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 60_000),
      # 5 minutes
      max_idle_time: Keyword.get(opts, :max_idle_time, 300_000)
    }

    # Start cleanup timer
    schedule_cleanup()

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_connection, provider}, _from, state) do
    connection_key = build_connection_key(provider)

    case Map.get(state.connections, connection_key) do
      nil ->
        # Create new connection
        case create_connection(provider, state) do
          {:ok, pid} ->
            new_connections = Map.put(state.connections, connection_key, pid)
            new_state = %{state | connections: new_connections}
            {:reply, {:ok, pid}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      pid ->
        # Check if connection is still alive and healthy
        if Process.alive?(pid) and Connection.healthy?(pid) do
          {:reply, {:ok, pid}, state}
        else
          # Connection is dead, create a new one
          new_connections = Map.delete(state.connections, connection_key)
          new_state = %{state | connections: new_connections}

          case create_connection(provider, new_state) do
            {:ok, new_pid} ->
              updated_connections = Map.put(new_connections, connection_key, new_pid)
              {:reply, {:ok, new_pid}, %{new_state | connections: updated_connections}}

            {:error, reason} ->
              {:reply, {:error, reason}, new_state}
          end
        end
    end
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      total_connections: map_size(state.connections),
      max_connections: state.max_connections,
      connection_keys: Map.keys(state.connections)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast({:return_connection, _pid}, state) do
    # Connection is returned to pool, no action needed
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:close_connection, pid}, state) do
    # Find and remove the connection
    new_connections =
      state.connections
      |> Enum.reject(fn {_key, connection_pid} -> connection_pid == pid end)
      |> Map.new()

    # Close the connection
    if Process.alive?(pid) do
      Connection.close(pid)
    end

    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_cast(:close_all_connections, state) do
    # Close all connections
    Enum.each(state.connections, fn {_key, pid} ->
      if Process.alive?(pid) do
        Connection.close(pid)
      end
    end)

    {:noreply, %{state | connections: %{}}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Clean up idle connections
    now = DateTime.utc_now()
    max_idle_time = state.max_idle_time

    {active_connections, closed_count} =
      state.connections
      |> Enum.reduce({%{}, 0}, fn {key, pid}, {acc, closed} ->
        if Process.alive?(pid) do
          # Check if connection is idle
          case get_connection_last_used(pid) do
            {:ok, last_used} ->
              idle_time = DateTime.diff(now, last_used, :millisecond)

              if idle_time > max_idle_time do
                Connection.close(pid)
                {acc, closed + 1}
              else
                {Map.put(acc, key, pid), closed}
              end

            {:error, _} ->
              # Connection is not responding, close it
              Connection.close(pid)
              {acc, closed + 1}
          end
        else
          {acc, closed + 1}
        end
      end)

    if closed_count > 0 do
      Logger.info("Cleaned up #{closed_count} idle gRPC connections")
    end

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, %{state | connections: active_connections}}
  end

  # Private functions

  defp create_connection(provider, state) do
    if map_size(state.connections) >= state.max_connections do
      {:error, "Maximum number of connections reached"}
    else
      opts = [
        max_retries: 3,
        connection_timeout: state.connection_timeout
      ]

      case Connection.start_link(provider, opts) do
        {:ok, pid} -> {:ok, pid}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_connection_key(provider) do
    host = Map.get(provider, :host, "localhost")
    port = Map.get(provider, :port, 50051)
    use_ssl = Map.get(provider, :use_ssl, false)
    service_name = Map.get(provider, :service_name, "UTCPService")

    "#{host}:#{port}:#{use_ssl}:#{service_name}"
  end

  defp get_connection_last_used(pid) do
    GenServer.call(pid, :last_used, 1000)
  rescue
    _ -> {:error, :timeout}
  end

  defp schedule_cleanup do
    # 1 minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end
