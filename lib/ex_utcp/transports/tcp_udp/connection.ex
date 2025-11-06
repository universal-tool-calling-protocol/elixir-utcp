defmodule ExUtcp.Transports.TcpUdp.Connection do
  @moduledoc """
  Manages individual TCP/UDP connections.

  This module handles the low-level network communication for both TCP and UDP protocols.
  It provides message serialization, connection management, and error handling.
  """

  use GenServer
  use ExUtcp.Transports.TcpUdp.ConnectionBehaviour

  defstruct [
    :socket,
    :provider,
    :last_used,
    :protocol,
    :host,
    :port,
    :buffer
  ]

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def start_link(provider) do
    GenServer.start_link(__MODULE__, provider)
  end

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def call_tool(conn, tool_name, args, timeout) do
    GenServer.call(conn, {:call_tool, tool_name, args, timeout})
  end

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def call_tool_stream(conn, tool_name, args, timeout) do
    GenServer.call(conn, {:call_tool_stream, tool_name, args, timeout})
  end

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def close(conn) do
    GenServer.call(conn, :close)
  end

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def get_last_used(conn) do
    GenServer.call(conn, :get_last_used)
  end

  @impl ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  def update_last_used(conn) do
    GenServer.cast(conn, :update_last_used)
  end

  # GenServer callbacks

  @impl GenServer
  def init(provider) do
    case establish_connection(provider) do
      {:ok, socket} ->
        state = %__MODULE__{
          socket: socket,
          provider: provider,
          last_used: System.monotonic_time(:millisecond),
          protocol: provider.protocol,
          host: provider.host,
          port: provider.port,
          buffer: ""
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:error, reason}}
    end
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, timeout}, _from, state) do
    case execute_tool_call(tool_name, args, state, timeout) do
      {:ok, result} ->
        new_state = %{state | last_used: System.monotonic_time(:millisecond)}
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, timeout}, _from, state) do
    case execute_tool_stream(tool_name, args, state, timeout) do
      {:ok, stream} ->
        new_state = %{state | last_used: System.monotonic_time(:millisecond)}
        {:reply, {:ok, stream}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_last_used, _from, state) do
    {:reply, state.last_used, state}
  end

  @impl GenServer
  def handle_cast(:update_last_used, state) do
    new_state = %{state | last_used: System.monotonic_time(:millisecond)}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tcp, _socket, data}, state) do
    new_buffer = state.buffer <> data
    new_state = %{state | buffer: new_buffer}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    new_buffer = state.buffer <> data
    new_state = %{state | buffer: new_buffer}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:udp_error, _socket, reason}, state) do
    {:stop, reason, state}
  end

  # Private functions

  defp establish_connection(provider) do
    case provider.protocol do
      :tcp -> establish_tcp_connection(provider)
      :udp -> establish_udp_connection(provider)
      _ -> {:error, "Unsupported protocol: #{provider.protocol}"}
    end
  end

  defp establish_tcp_connection(provider) do
    host = String.to_charlist(provider.host)
    port = provider.port
    timeout = Map.get(provider, :timeout, 5000)

    case :gen_tcp.connect(host, port, [:binary, active: true], timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, "TCP connection failed: #{inspect(reason)}"}
    end
  end

  defp establish_udp_connection(provider) do
    case :gen_udp.open(0) do
      {:ok, socket} ->
        # Try to send a test packet to verify connectivity
        case :gen_udp.send(socket, to_charlist(provider.host), provider.port, "test") do
          :ok ->
            {:ok, socket}

          {:error, reason} ->
            :gen_udp.close(socket)
            {:error, "UDP connection failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "UDP socket creation failed: #{inspect(reason)}"}
    end
  end

  defp execute_tool_call(tool_name, args, state, timeout) do
    message = build_message(tool_name, args, state.provider)

    case send_message(message, state) do
      {:ok, _} ->
        case receive_response(timeout) do
          {:ok, response} ->
            case parse_response(response) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, "Failed to parse response: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to receive response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end

  defp execute_tool_stream(tool_name, args, state, timeout) do
    message = build_message(tool_name, args, state.provider)

    case send_message(message, state) do
      {:ok, _} ->
        # For streaming, we'll simulate by returning a stream of chunks
        stream = create_stream_from_response(state, timeout)
        {:ok, stream}

      {:error, reason} ->
        {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end

  defp build_message(tool_name, args, provider) do
    %{
      tool: tool_name,
      args: args,
      timestamp: System.monotonic_time(:millisecond),
      protocol: provider.protocol
    }
  end

  defp send_message(message, state) do
    encoded_message = Jason.encode!(message)

    case state.protocol do
      :tcp -> send_tcp_message(encoded_message, state)
      :udp -> send_udp_message(encoded_message, state)
    end
  end

  defp send_tcp_message(message, state) do
    case :gen_tcp.send(state.socket, message) do
      :ok -> {:ok, :sent}
      {:error, reason} -> {:error, "TCP send failed: #{inspect(reason)}"}
    end
  end

  defp send_udp_message(message, state) do
    host = String.to_charlist(state.host)
    port = state.port

    case :gen_udp.send(state.socket, host, port, message) do
      :ok -> {:ok, :sent}
      {:error, reason} -> {:error, "UDP send failed: #{inspect(reason)}"}
    end
  end

  defp receive_response(timeout) do
    receive do
      {:tcp, _socket, data} -> {:ok, data}
      {:udp, _socket, _ip, _port, data} -> {:ok, data}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp parse_response(response) do
    case Jason.decode(response) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp create_stream_from_response(state, timeout) do
    Stream.resource(
      fn -> {state, timeout} end,
      fn {state, remaining_timeout} ->
        case receive_response(remaining_timeout) do
          {:ok, data} ->
            case parse_response(data) do
              {:ok, result} ->
                {[%{type: :stream, data: result}], {state, remaining_timeout}}

              {:error, _} ->
                {[%{type: :error, error: "Parse error"}], {state, remaining_timeout}}
            end

          {:error, :timeout} ->
            {[%{type: :end}], {state, 0}}

          {:error, reason} ->
            {[%{type: :error, error: reason}], {state, 0}}
        end
      end,
      fn _state -> :ok end
    )
  end
end
