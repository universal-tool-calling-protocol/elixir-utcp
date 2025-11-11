defmodule ExUtcp.Transports.WebRTC.Connection do
  @moduledoc """
  WebRTC peer connection management for UTCP.

  Handles:
  - Peer connection establishment with signaling
  - ICE candidate exchange and NAT traversal
  - Data channel creation and management
  - Tool call communication over data channels
  """

  use GenServer

  alias ExUtcp.Transports.WebRTC.Signaling
  alias ExWebRTC.DataChannel
  alias ExWebRTC.ICECandidate
  alias ExWebRTC.PeerConnection
  alias ExWebRTC.SessionDescription

  require Logger

  @enforce_keys [:provider, :signaling_server, :ice_servers]
  defstruct [
    :provider,
    :signaling_server,
    :ice_servers,
    :peer_connection,
    :data_channel,
    :signaling_pid,
    :connection_state,
    :ice_connection_state,
    :pending_calls,
    :call_id_counter
  ]

  @type t :: %__MODULE__{
          provider: map(),
          signaling_server: String.t(),
          ice_servers: [map()],
          peer_connection: pid() | nil,
          data_channel: pid() | nil,
          signaling_pid: pid() | nil,
          connection_state: atom(),
          ice_connection_state: atom(),
          pending_calls: %{String.t() => pid()},
          call_id_counter: integer()
        }

  @doc """
  Starts a new WebRTC connection.
  """
  @spec start_link(map(), String.t(), [map()]) :: {:ok, pid()} | {:error, term()}
  def start_link(provider, signaling_server, ice_servers) do
    GenServer.start_link(__MODULE__, {provider, signaling_server, ice_servers})
  end

  @doc """
  Calls a tool over the WebRTC data channel.
  """
  @spec call_tool(pid(), String.t(), map(), integer()) :: {:ok, map()} | {:error, term()}
  def call_tool(pid, tool_name, args, timeout \\ 30_000) do
    GenServer.call(pid, {:call_tool, tool_name, args}, timeout)
  end

  @doc """
  Calls a tool stream over the WebRTC data channel.
  """
  @spec call_tool_stream(pid(), String.t(), map(), integer()) ::
          {:ok, Stream.t()} | {:error, term()}
  def call_tool_stream(pid, tool_name, args, timeout \\ 30_000) do
    GenServer.call(pid, {:call_tool_stream, tool_name, args}, timeout)
  end

  @doc """
  Closes the WebRTC connection.
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Gets the connection state.
  """
  @spec get_connection_state(pid()) :: atom()
  def get_connection_state(pid) do
    GenServer.call(pid, :get_connection_state)
  end

  @doc """
  Gets the ICE connection state.
  """
  @spec get_ice_connection_state(pid()) :: atom()
  def get_ice_connection_state(pid) do
    GenServer.call(pid, :get_ice_connection_state)
  end

  # GenServer callbacks

  @impl GenServer
  def init({provider, signaling_server, ice_servers}) do
    state = %__MODULE__{
      provider: provider,
      signaling_server: signaling_server,
      ice_servers: ice_servers,
      peer_connection: nil,
      data_channel: nil,
      signaling_pid: nil,
      connection_state: :new,
      ice_connection_state: :new,
      pending_calls: %{},
      call_id_counter: 0
    }

    # Start connection establishment asynchronously
    send(self(), :establish_connection)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args}, from, state) do
    if state.connection_state == :connected and state.data_channel != nil do
      # Generate unique call ID
      call_id = "call_#{state.call_id_counter}"

      # Create tool call message
      message = %{
        id: call_id,
        type: "tool_call",
        tool: tool_name,
        args: args
      }

      # Send message over data channel
      case send_data_channel_message(state.data_channel, message) do
        :ok ->
          # Store pending call
          new_pending_calls = Map.put(state.pending_calls, call_id, from)

          new_state = %{
            state
            | pending_calls: new_pending_calls,
              call_id_counter: state.call_id_counter + 1
          }

          {:noreply, new_state}

        {:error, reason} ->
          {:reply, {:error, "Failed to send message: #{inspect(reason)}"}, state}
      end
    else
      {:reply, {:error, "Connection not ready. State: #{state.connection_state}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args}, _from, state) do
    if state.connection_state == :connected and state.data_channel != nil do
      # For streaming, we'll create a stream that polls for chunks
      stream = create_polling_stream(state.data_channel, tool_name, args)
      {:reply, {:ok, stream}, state}
    else
      {:reply, {:error, "Connection not ready. State: #{state.connection_state}"}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_connection_state, _from, state) do
    {:reply, state.connection_state, state}
  end

  @impl GenServer
  def handle_call(:get_ice_connection_state, _from, state) do
    {:reply, state.ice_connection_state, state}
  end

  @impl GenServer
  def handle_info(:establish_connection, state) do
    Logger.info("Establishing WebRTC connection for provider: #{state.provider.name}")

    try do
      # Create peer connection
      {:ok, pc} =
        PeerConnection.start_link(
          ice_servers: state.ice_servers,
          ice_transport_policy: :all
        )

      # Create data channel
      {:ok, dc} =
        PeerConnection.create_data_channel(pc, "utcp_channel", %{
          ordered: true,
          max_retransmits: 3
        })

      # Connect to signaling server
      {:ok, signaling_pid} = Signaling.start_link(state.signaling_server, self())

      # Create and send offer
      {:ok, offer} = PeerConnection.create_offer(pc)
      :ok = PeerConnection.set_local_description(pc, offer)

      # Send offer through signaling
      :ok = Signaling.send_offer(signaling_pid, offer, state.provider.peer_id)

      new_state = %{
        state
        | peer_connection: pc,
          data_channel: dc,
          signaling_pid: signaling_pid,
          connection_state: :connecting
      }

      {:noreply, new_state}
    rescue
      error ->
        Logger.error("Failed to establish WebRTC connection: #{inspect(error)}")
        {:noreply, %{state | connection_state: :failed}}
    end
  end

  @impl GenServer
  def handle_info({:signaling, :answer, answer}, state) do
    # Received answer from remote peer
    case PeerConnection.set_remote_description(state.peer_connection, answer) do
      :ok ->
        Logger.info("Remote description set successfully")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to set remote description: #{inspect(reason)}")
        {:noreply, %{state | connection_state: :failed}}
    end
  end

  @impl GenServer
  def handle_info({:signaling, :ice_candidate, candidate}, state) do
    # Received ICE candidate from remote peer
    case PeerConnection.add_ice_candidate(state.peer_connection, candidate) do
      :ok ->
        Logger.debug("ICE candidate added successfully")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to add ICE candidate: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    # Local ICE candidate generated, send to remote peer
    case Signaling.send_ice_candidate(state.signaling_pid, candidate, state.provider.peer_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send ICE candidate: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _pc, {:connection_state_change, new_state}}, state) do
    Logger.info("WebRTC connection state changed: #{new_state}")
    {:noreply, %{state | connection_state: new_state}}
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _pc, {:ice_connection_state_change, new_state}}, state) do
    Logger.info("ICE connection state changed: #{new_state}")
    {:noreply, %{state | ice_connection_state: new_state}}
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _dc, {:data, data}}, state) do
    # Received data from data channel
    case Jason.decode(data) do
      {:ok, message} ->
        handle_data_channel_message(message, state)

      {:error, reason} ->
        Logger.error("Failed to decode data channel message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _dc, :open}, state) do
    Logger.info("Data channel opened")
    {:noreply, %{state | connection_state: :connected}}
  end

  @impl GenServer
  def handle_info({:ex_webrtc, _dc, :closed}, state) do
    Logger.info("Data channel closed")
    {:noreply, %{state | connection_state: :closed}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("Unhandled WebRTC message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helper functions

  defp handle_data_channel_message(
         %{"id" => call_id, "type" => "response", "result" => result},
         state
       ) do
    # Handle tool call response
    case Map.get(state.pending_calls, call_id) do
      nil ->
        Logger.warning("Received response for unknown call ID: #{call_id}")
        {:noreply, state}

      from ->
        GenServer.reply(from, {:ok, result})
        new_pending_calls = Map.delete(state.pending_calls, call_id)
        {:noreply, %{state | pending_calls: new_pending_calls}}
    end
  end

  defp handle_data_channel_message(%{"id" => call_id, "type" => "error", "error" => error}, state) do
    # Handle tool call error
    case Map.get(state.pending_calls, call_id) do
      nil ->
        Logger.warning("Received error for unknown call ID: #{call_id}")
        {:noreply, state}

      from ->
        GenServer.reply(from, {:error, error})
        new_pending_calls = Map.delete(state.pending_calls, call_id)
        {:noreply, %{state | pending_calls: new_pending_calls}}
    end
  end

  defp handle_data_channel_message(message, state) do
    Logger.debug("Received unhandled data channel message: #{inspect(message)}")
    {:noreply, state}
  end

  defp send_data_channel_message(data_channel, message) do
    case Jason.encode(message) do
      {:ok, json} ->
        DataChannel.send_data(data_channel, json)

      {:error, reason} ->
        {:error, "Failed to encode message: #{inspect(reason)}"}
    end
  end

  defp create_polling_stream(data_channel, tool_name, args) do
    # Create a stream that polls for streaming chunks
    # This is a simplified implementation
    Stream.resource(
      fn ->
        # Initialize: send streaming request
        message = %{
          id: "stream_#{:rand.uniform(1_000_000)}",
          type: "tool_call_stream",
          tool: tool_name,
          args: args
        }

        send_data_channel_message(data_channel, message)
        {data_channel, []}
      end,
      fn {dc, buffer} ->
        # Poll for chunks (simplified - in real implementation would use message handlers)
        Process.sleep(10)

        # Check if we have buffered chunks
        if Enum.empty?(buffer) do
          {:halt, {dc, buffer}}
        else
          {[hd(buffer)], {dc, tl(buffer)}}
        end
      end,
      fn {_dc, _buffer} ->
        # Cleanup
        :ok
      end
    )
  end
end
