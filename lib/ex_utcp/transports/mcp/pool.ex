defmodule ExUtcp.Transports.Mcp.Pool do
  @moduledoc """
  Manages a pool of MCP connections for efficient resource usage.
  """

  use GenServer

  alias ExUtcp.Transports.Mcp.Connection

  require Logger

  defstruct [
    :connections,
    :max_connections,
    :connection_timeout,
    :cleanup_interval
  ]

  @doc """
  Starts the MCP connection pool.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a connection for the given provider.
  """
  @spec get_connection(ExUtcp.Types.mcp_provider()) :: {:ok, pid()} | {:error, String.t()}
  def get_connection(provider) do
    GenServer.call(__MODULE__, {:get_connection, provider})
  end

  @doc """
  Closes a specific connection.
  """
  @spec close_connection(pid()) :: :ok
  def close_connection(pid) do
    GenServer.call(__MODULE__, {:close_connection, pid})
  end

  @doc """
  Closes all connections.
  """
  @spec close_all_connections() :: :ok
  def close_all_connections do
    GenServer.call(__MODULE__, :close_all_connections)
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
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 60_000)
    }

    # Start cleanup timer
    cleanup_timer = Process.send_after(self(), :cleanup, state.cleanup_interval)

    {:ok, Map.put(state, :cleanup_timer, cleanup_timer)}
  end

  @impl GenServer
  def handle_call({:get_connection, provider}, _from, state) do
    provider_key = build_provider_key(provider)

    case Map.get(state.connections, provider_key) do
      nil ->
        case create_connection(provider, state) do
          {:ok, pid} ->
            new_connections = Map.put(state.connections, provider_key, pid)
            new_state = %{state | connections: new_connections}
            {:reply, {:ok, pid}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      pid ->
        # Check if connection is still alive
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          # Connection is dead, create a new one
          case create_connection(provider, state) do
            {:ok, new_pid} ->
              new_connections = Map.put(state.connections, provider_key, new_pid)
              new_state = %{state | connections: new_connections}
              {:reply, {:ok, new_pid}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  @impl GenServer
  def handle_call({:close_connection, pid}, _from, state) do
    # Find and remove the connection
    new_connections =
      Enum.reject(state.connections, fn {_key, connection_pid} ->
        connection_pid == pid
      end)
      |> Map.new()

    # Close the connection if it's still alive
    if Process.alive?(pid) do
      Connection.close(pid)
    end

    new_state = %{state | connections: new_connections}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:close_all_connections, _from, state) do
    # Close all connections
    Enum.each(state.connections, fn {_key, pid} ->
      if Process.alive?(pid) do
        Connection.close(pid)
      end
    end)

    new_state = %{state | connections: %{}}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      total_connections: map_size(state.connections),
      max_connections: state.max_connections,
      connections: Map.keys(state.connections)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Clean up dead connections
    alive_connections =
      Enum.filter(state.connections, fn {_key, pid} ->
        Process.alive?(pid)
      end)
      |> Map.new()

    new_state = %{state | connections: alive_connections}

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, state.cleanup_interval)
    new_state = Map.put(new_state, :cleanup_timer, cleanup_timer)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead connection from pool
    new_connections =
      Enum.reject(state.connections, fn {_key, connection_pid} ->
        connection_pid == pid
      end)
      |> Map.new()

    new_state = %{state | connections: new_connections}
    {:noreply, new_state}
  end

  # Private functions

  defp create_connection(provider, state) do
    if map_size(state.connections) >= state.max_connections do
      {:error, "Maximum number of connections reached"}
    else
      case Connection.start_link(provider) do
        {:ok, pid} ->
          # Monitor the connection
          Process.monitor(pid)
          {:ok, pid}

        {:error, reason} ->
          {:error, "Failed to create connection: #{inspect(reason)}"}
      end
    end
  end

  defp build_provider_key(provider) do
    "#{provider.name}:#{provider.url}"
  end
end
