defmodule ExUtcp.Transports.TcpUdp.Pool do
  @moduledoc """
  Manages a pool of TCP/UDP connections.

  This module provides connection pooling for TCP/UDP connections to improve
  performance and resource management.
  """

  use GenServer
  use ExUtcp.Transports.TcpUdp.PoolBehaviour

  alias ExUtcp.Transports.TcpUdp.Connection

  defstruct [
    :connections,
    :max_connections,
    :connection_timeout
  ]

  @impl ExUtcp.Transports.TcpUdp.PoolBehaviour
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl ExUtcp.Transports.TcpUdp.PoolBehaviour
  def get_connection(pool_pid, provider) do
    GenServer.call(pool_pid, {:get_connection, provider})
  end

  @impl ExUtcp.Transports.TcpUdp.PoolBehaviour
  def close_connection(pool_pid, conn_pid) do
    GenServer.call(pool_pid, {:close_connection, conn_pid})
  end

  @impl ExUtcp.Transports.TcpUdp.PoolBehaviour
  def close_all_connections(pool_pid) do
    GenServer.call(pool_pid, :close_all_connections)
  end

  @impl ExUtcp.Transports.TcpUdp.PoolBehaviour
  def stats(pool_pid) do
    GenServer.call(pool_pid, :stats)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    max_connections = Keyword.get(opts, :max_connections, 10)
    connection_timeout = Keyword.get(opts, :connection_timeout, 30_000)

    state = %__MODULE__{
      connections: %{},
      max_connections: max_connections,
      connection_timeout: connection_timeout
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_connection, provider}, _from, state) do
    case get_or_create_connection(provider, state) do
      {:ok, conn_pid, new_state} ->
        {:reply, {:ok, conn_pid}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:close_connection, conn_pid}, _from, state) do
    case Map.get(state.connections, conn_pid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _provider ->
        Connection.close(conn_pid)
        new_connections = Map.delete(state.connections, conn_pid)
        new_state = %{state | connections: new_connections}
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:close_all_connections, _from, state) do
    Enum.each(state.connections, fn {conn_pid, _provider} ->
      Connection.close(conn_pid)
    end)

    new_state = %{state | connections: %{}}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      total_connections: map_size(state.connections),
      max_connections: state.max_connections,
      connection_timeout: state.connection_timeout
    }

    {:reply, stats, state}
  end

  # Private functions

  defp get_or_create_connection(provider, state) do
    # Check if we already have a connection for this provider
    case find_existing_connection(provider, state) do
      {:ok, conn_pid} ->
        {:ok, conn_pid, state}

      :not_found ->
        create_new_connection(provider, state)
    end
  end

  defp find_existing_connection(provider, state) do
    case Enum.find(state.connections, fn {_pid, conn_provider} ->
           conn_provider.name == provider.name and conn_provider.protocol == provider.protocol
         end) do
      {conn_pid, _provider} -> {:ok, conn_pid}
      nil -> :not_found
    end
  end

  defp create_new_connection(provider, state) do
    if map_size(state.connections) >= state.max_connections do
      {:error, "Maximum connections reached"}
    else
      case Connection.start_link(provider) do
        {:ok, conn_pid} ->
          new_connections = Map.put(state.connections, conn_pid, provider)
          new_state = %{state | connections: new_connections}
          {:ok, conn_pid, new_state}

        {:error, reason} ->
          {:error, "Failed to create connection: #{inspect(reason)}"}
      end
    end
  end
end
