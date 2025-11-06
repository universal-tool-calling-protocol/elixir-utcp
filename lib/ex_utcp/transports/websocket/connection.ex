defmodule ExUtcp.Transports.WebSocket.Connection do
  @moduledoc """
  WebSocket connection handler for UTCP transport.

  This module handles individual WebSocket connections and implements
  the WebSockex behavior for managing WebSocket state and messages.
  """

  @behaviour ExUtcp.Transports.WebSocket.ConnectionBehaviour

  use WebSockex

  require Logger

  defstruct [
    :provider,
    :transport_pid,
    :message_queue,
    :connection_state,
    :last_ping,
    :ping_interval
  ]

  @doc """
  Starts a new WebSocket connection.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec start_link(map()) :: {:ok, pid()} | {:error, term()}
  def start_link(provider) do
    start_link(provider.url, provider, [])
  end

  @spec start_link(String.t(), map(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(url, provider, opts \\ []) do
    state = %__MODULE__{
      provider: provider,
      transport_pid: Keyword.get(opts, :transport_pid),
      message_queue: :queue.new(),
      connection_state: :connecting,
      last_ping: nil,
      ping_interval: Keyword.get(opts, :ping_interval, 30_000)
    }

    WebSockex.start_link(url, __MODULE__, state, opts)
  end

  @doc """
  Sends a message through the WebSocket connection.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec send_message(pid(), String.t()) :: :ok | {:error, term()}
  def send_message(pid, message) do
    WebSockex.send_frame(pid, {:text, message})
  end

  @doc """
  Closes the WebSocket connection.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid)
  end

  # WebSockex callbacks

  @impl WebSockex
  def handle_connect(conn, state) do
    Logger.info("WebSocket connected to #{inspect(conn)}")

    # Start ping timer
    if state.ping_interval > 0 do
      Process.send_after(self(), :ping, state.ping_interval)
    end

    new_state = %{state | connection_state: :connected}
    {:ok, new_state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    Logger.info("WebSocket disconnected: #{inspect(disconnect_map)}")

    # Notify transport about disconnection
    if state.transport_pid do
      send(state.transport_pid, {:websocket, self(), :close})
    end

    new_state = %{state | connection_state: :disconnected}
    {:ok, new_state}
  end

  @impl WebSockex
  def handle_frame({:text, message}, state) do
    Logger.debug("Received WebSocket message: #{message}")

    # Notify transport about incoming message
    if state.transport_pid do
      send(state.transport_pid, {:websocket, self(), {:text, message}})
    end

    # Add message to queue for synchronous operations
    new_queue = :queue.in(message, state.message_queue)
    new_state = %{state | message_queue: new_queue}
    {:ok, new_state}
  end

  @impl WebSockex
  def handle_frame({:binary, data}, state) do
    Logger.debug("Received WebSocket binary data: #{inspect(data)}")

    # Notify transport about incoming binary data
    if state.transport_pid do
      send(state.transport_pid, {:websocket, self(), {:binary, data}})
    end

    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:ping, payload}, state) do
    Logger.debug("Received WebSocket ping: #{inspect(payload)}")
    {:reply, {:pong, payload}, state}
  end

  @impl WebSockex
  def handle_frame({:pong, payload}, state) do
    Logger.debug("Received WebSocket pong: #{inspect(payload)}")
    new_state = %{state | last_ping: :os.system_time(:millisecond)}
    {:ok, new_state}
  end

  @impl WebSockex
  def handle_info(:ping, state) do
    case state.connection_state do
      :connected ->
        # Send ping frame
        {:reply, {:ping, "ping"}, state}

      _ ->
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_info({:send_message, message}, state) do
    {:reply, {:text, message}, state}
  end

  @impl WebSockex
  def handle_info(:close, state) do
    {:close, state}
  end

  @impl WebSockex
  def handle_info(msg, state) do
    Logger.warning("Unhandled WebSocket info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.info("WebSocket connection terminated: #{inspect(reason)}")

    # Notify transport about termination
    if state.transport_pid do
      send(state.transport_pid, {:websocket, self(), {:error, reason}})
    end

    :ok
  end

  # Helper functions

  @doc """
  Gets the next message from the message queue.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec get_next_message(pid(), timeout()) :: {:ok, String.t()} | {:error, :timeout}
  def get_next_message(pid, timeout \\ 5_000) do
    case GenServer.call(pid, :get_next_message, timeout) do
      {:ok, message} -> {:ok, message}
      {:error, :empty} -> {:error, :timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets all messages from the message queue.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec get_all_messages(pid()) :: [String.t()]
  def get_all_messages(pid) do
    GenServer.call(pid, :get_all_messages)
  end

  @doc """
  Clears the message queue.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec clear_messages(pid()) :: :ok
  def clear_messages(pid) do
    GenServer.call(pid, :clear_messages)
  end

  @doc """
  Calls a tool through the WebSocket connection.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec call_tool(pid(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call_tool(pid, tool_name, args, opts \\ []) do
    message = %{
      type: "tool_call",
      tool: tool_name,
      args: args
    }

    case send_message(pid, Jason.encode!(message)) do
      :ok ->
        case get_next_message(pid, Keyword.get(opts, :timeout, 30_000)) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calls a tool stream through the WebSocket connection.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec call_tool_stream(pid(), String.t(), map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def call_tool_stream(pid, tool_name, args, opts \\ []) do
    message = %{
      type: "tool_stream",
      tool: tool_name,
      args: args
    }

    case send_message(pid, Jason.encode!(message)) do
      :ok ->
        stream =
          Stream.unfold(nil, fn _ ->
            case get_next_message(pid, Keyword.get(opts, :timeout, 5_000)) do
              {:ok, %{"type" => "stream_end"}} -> nil
              {:ok, data} -> {data, nil}
              {:error, _} -> nil
            end
          end)

        {:ok, stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the last used timestamp.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec get_last_used(pid()) :: integer()
  def get_last_used(pid) do
    GenServer.call(pid, :get_last_used)
  end

  @doc """
  Updates the last used timestamp.
  """
  @impl ExUtcp.Transports.WebSocket.ConnectionBehaviour
  @spec update_last_used(pid()) :: :ok
  def update_last_used(pid) do
    GenServer.cast(pid, :update_last_used)
  end

  # GenServer callbacks for message queue management

  def handle_call(:get_next_message, _from, state) do
    case :queue.out(state.message_queue) do
      {{:value, message}, new_queue} ->
        new_state = %{state | message_queue: new_queue}
        {:reply, {:ok, message}, new_state}

      {:empty, _} ->
        {:reply, {:error, :empty}, state}
    end
  end

  def handle_call(:get_all_messages, _from, state) do
    messages = :queue.to_list(state.message_queue)
    new_state = %{state | message_queue: :queue.new()}
    {:reply, messages, new_state}
  end

  def handle_call(:clear_messages, _from, state) do
    new_state = %{state | message_queue: :queue.new()}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_last_used, _from, state) do
    {:reply, state.last_ping || System.monotonic_time(:millisecond), state}
  end

  def handle_call(msg, _from, state) do
    Logger.warning("Unhandled WebSocket call: #{inspect(msg)}")
    {:reply, {:error, :not_implemented}, state}
  end

  def handle_cast(:update_last_used, state) do
    new_state = %{state | last_ping: System.monotonic_time(:millisecond)}
    {:noreply, new_state}
  end

  def handle_cast(msg, state) do
    Logger.warning("Unhandled WebSocket cast: #{inspect(msg)}")
    {:noreply, state}
  end
end
