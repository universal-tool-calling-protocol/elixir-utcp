defmodule ExUtcp.Transports.WebRTC.Signaling do
  @moduledoc """
  WebRTC signaling server client for exchanging SDP and ICE candidates.

  Handles communication with the signaling server for:
  - SDP offer/answer exchange
  - ICE candidate exchange
  - Peer discovery and connection establishment
  """

  use GenServer

  require Logger

  @enforce_keys [:server_url, :parent_pid]
  defstruct [
    :server_url,
    :parent_pid,
    :websocket_pid,
    :peer_id,
    :connection_state
  ]

  @type t :: %__MODULE__{
          server_url: String.t(),
          parent_pid: pid(),
          websocket_pid: pid() | nil,
          peer_id: String.t() | nil,
          connection_state: atom()
        }

  @doc """
  Starts the signaling client.
  """
  @spec start_link(String.t(), pid()) :: {:ok, pid()} | {:error, term()}
  def start_link(server_url, parent_pid) do
    GenServer.start_link(__MODULE__, {server_url, parent_pid})
  end

  @doc """
  Sends an SDP offer to the remote peer.
  """
  @spec send_offer(pid(), map(), String.t()) :: :ok | {:error, term()}
  def send_offer(pid, offer, peer_id) do
    GenServer.call(pid, {:send_offer, offer, peer_id})
  end

  @doc """
  Sends an SDP answer to the remote peer.
  """
  @spec send_answer(pid(), map(), String.t()) :: :ok | {:error, term()}
  def send_answer(pid, answer, peer_id) do
    GenServer.call(pid, {:send_answer, answer, peer_id})
  end

  @doc """
  Sends an ICE candidate to the remote peer.
  """
  @spec send_ice_candidate(pid(), map(), String.t()) :: :ok | {:error, term()}
  def send_ice_candidate(pid, candidate, peer_id) do
    GenServer.call(pid, {:send_ice_candidate, candidate, peer_id})
  end

  @doc """
  Closes the signaling connection.
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid)
  end

  # GenServer callbacks

  @impl GenServer
  def init({server_url, parent_pid}) do
    state = %__MODULE__{
      server_url: server_url,
      parent_pid: parent_pid,
      websocket_pid: nil,
      peer_id: nil,
      connection_state: :disconnected
    }

    # Connect to signaling server asynchronously
    send(self(), :connect_to_signaling_server)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:send_offer, offer, peer_id}, _from, state) do
    message = %{
      type: "offer",
      sdp: offer.sdp,
      to: peer_id,
      from: state.peer_id
    }

    case send_signaling_message(state.websocket_pid, message) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_answer, answer, peer_id}, _from, state) do
    message = %{
      type: "answer",
      sdp: answer.sdp,
      to: peer_id,
      from: state.peer_id
    }

    case send_signaling_message(state.websocket_pid, message) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_ice_candidate, candidate, peer_id}, _from, state) do
    message = %{
      type: "ice_candidate",
      candidate: %{
        candidate: candidate.candidate,
        sdp_mid: candidate.sdp_mid,
        sdp_m_line_index: candidate.sdp_m_line_index
      },
      to: peer_id,
      from: state.peer_id
    }

    case send_signaling_message(state.websocket_pid, message) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect_to_signaling_server, state) do
    Logger.info("Connecting to signaling server: #{state.server_url}")

    try do
      # In a real implementation, this would establish a WebSocket connection
      # For now, we'll simulate it
      peer_id = generate_peer_id()

      new_state = %{state | peer_id: peer_id, connection_state: :connected}

      Logger.info("Connected to signaling server with peer ID: #{peer_id}")
      {:noreply, new_state}
    rescue
      error ->
        Logger.error("Failed to connect to signaling server: #{inspect(error)}")

        # Retry after delay
        Process.send_after(self(), :connect_to_signaling_server, 5000)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:websocket, :message, data}, state) do
    # Handle incoming signaling messages
    case Jason.decode(data) do
      {:ok, message} ->
        handle_signaling_message(message, state)

      {:error, reason} ->
        Logger.error("Failed to decode signaling message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("Unhandled signaling message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp handle_signaling_message(%{"type" => "answer", "sdp" => sdp}, state) do
    # Forward answer to parent (WebRTC connection)
    answer = %{type: :answer, sdp: sdp}
    send(state.parent_pid, {:signaling, :answer, answer})
    {:noreply, state}
  end

  defp handle_signaling_message(%{"type" => "ice_candidate", "candidate" => candidate_data}, state) do
    # Forward ICE candidate to parent
    candidate = %{
      candidate: candidate_data["candidate"],
      sdp_mid: candidate_data["sdp_mid"],
      sdp_m_line_index: candidate_data["sdp_m_line_index"]
    }

    send(state.parent_pid, {:signaling, :ice_candidate, candidate})
    {:noreply, state}
  end

  defp handle_signaling_message(message, state) do
    Logger.debug("Unhandled signaling message type: #{inspect(message)}")
    {:noreply, state}
  end

  defp send_signaling_message(websocket_pid, message) do
    if websocket_pid == nil do
      {:error, "Signaling connection not established"}
      # In a real implementation, send via WebSocket
      # For now, we'll simulate success
    else
      case Jason.encode(message) do
        {:ok, _json} ->
          :ok

        {:error, reason} ->
          {:error, "Failed to encode message: #{inspect(reason)}"}
      end
    end
  end

  defp generate_peer_id do
    # Generate a unique peer ID
    "peer_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
