defmodule ExUtcp.Transports.WebRTC do
  @moduledoc """
  WebRTC transport for ExUtcp.

  Provides peer-to-peer communication using WebRTC data channels.
  Supports:
  - Peer-to-peer tool calling without server intermediary
  - Low-latency communication with NAT traversal
  - Secure communication with DTLS encryption
  - Multiple data channels for concurrent operations
  - ICE candidate exchange and STUN/TURN server support
  """

  use GenServer
  use ExUtcp.Transports.Behaviour

  alias ExUtcp.Transports.WebRTC.{Connection, Signaling}

  require Logger

  @enforce_keys [:signaling_server, :ice_servers, :connection_timeout]
  defstruct [
    :signaling_server,
    :ice_servers,
    :connection_timeout,
    :connections,
    :providers
  ]

  @type t :: %__MODULE__{
          signaling_server: String.t(),
          ice_servers: [map()],
          connection_timeout: integer(),
          connections: %{String.t() => pid()},
          providers: %{String.t() => map()}
        }

  @doc """
  Creates a new WebRTC transport.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      signaling_server: Keyword.get(opts, :signaling_server, "wss://signaling.example.com"),
      ice_servers: Keyword.get(opts, :ice_servers, default_ice_servers()),
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      connections: %{},
      providers: %{}
    }
  end

  @doc """
  Starts the WebRTC transport GenServer.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl ExUtcp.Transports.Behaviour
  def transport_name, do: "webrtc"

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming?, do: true

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :webrtc ->
        GenServer.call(__MODULE__, {:register_tool_provider, provider})

      _ ->
        {:error, "WebRTC transport can only be used with WebRTC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(provider) do
    case provider.type do
      :webrtc ->
        GenServer.call(__MODULE__, {:deregister_tool_provider, provider})

      _ ->
        {:error, "WebRTC transport can only be used with WebRTC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    case provider.type do
      :webrtc ->
        GenServer.call(
          __MODULE__,
          {:call_tool, tool_name, args, provider},
          provider.timeout || 30_000
        )

      _ ->
        {:error, "WebRTC transport can only be used with WebRTC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(tool_name, args, provider) do
    case provider.type do
      :webrtc ->
        GenServer.call(
          __MODULE__,
          {:call_tool_stream, tool_name, args, provider},
          provider.timeout || 30_000
        )

      _ ->
        {:error, "WebRTC transport can only be used with WebRTC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def close do
    GenServer.call(__MODULE__, :close)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    transport = new(opts)
    {:ok, transport}
  end

  @impl GenServer
  def handle_call({:register_tool_provider, provider}, _from, state) do
    case discover_tools(provider) do
      {:ok, tools} ->
        new_state = %{state | providers: Map.put(state.providers, provider.name, provider)}
        {:reply, {:ok, tools}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:deregister_tool_provider, provider}, _from, state) do
    # Close connection if exists
    case Map.get(state.connections, provider.name) do
      nil -> :ok
      conn_pid -> Connection.close(conn_pid)
    end

    new_state = %{
      state
      | providers: Map.delete(state.providers, provider.name),
        connections: Map.delete(state.connections, provider.name)
    }

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, provider}, _from, state) do
    case get_or_create_connection(provider, state) do
      {:ok, conn_pid, new_state} ->
        case Connection.call_tool(conn_pid, tool_name, args, provider.timeout || 30_000) do
          {:ok, result} ->
            {:reply, {:ok, result}, new_state}

          {:error, reason} ->
            {:reply, {:error, "Failed to call tool: #{inspect(reason)}"}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, "Failed to get connection: #{inspect(reason)}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, provider}, _from, state) do
    case get_or_create_connection(provider, state) do
      {:ok, conn_pid, new_state} ->
        case Connection.call_tool_stream(conn_pid, tool_name, args, provider.timeout || 30_000) do
          {:ok, stream} ->
            # Enhance the stream with WebRTC-specific metadata
            enhanced_stream = create_webrtc_stream(stream, tool_name, provider)

            {:reply,
             {:ok,
              %{
                type: :stream,
                data: enhanced_stream,
                metadata: %{"transport" => "webrtc", "tool" => tool_name}
              }}, new_state}

          {:error, reason} ->
            {:reply, {:error, "Failed to call tool stream: #{inspect(reason)}"}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, "Failed to get connection: #{inspect(reason)}"}, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    # Close all connections
    Enum.each(state.connections, fn {_name, conn_pid} ->
      Connection.close(conn_pid)
    end)

    {:reply, :ok, %{state | connections: %{}}}
  end

  # Private functions

  defp discover_tools(provider) do
    # For WebRTC, tools would be discovered through the signaling server
    # or provided in the provider configuration
    tools =
      case Map.get(provider, :tools) do
        nil -> []
        tools when is_list(tools) -> tools
        _ -> []
      end

    {:ok, tools}
  end

  defp get_or_create_connection(provider, state) do
    case Map.get(state.connections, provider.name) do
      nil ->
        # Create new connection
        case Connection.start_link(provider, state.signaling_server, state.ice_servers) do
          {:ok, conn_pid} ->
            new_connections = Map.put(state.connections, provider.name, conn_pid)
            new_state = %{state | connections: new_connections}
            {:ok, conn_pid, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      conn_pid ->
        # Reuse existing connection
        if Process.alive?(conn_pid) do
          {:ok, conn_pid, state}
        else
          # Connection died, create new one
          case Connection.start_link(provider, state.signaling_server, state.ice_servers) do
            {:ok, new_conn_pid} ->
              new_connections = Map.put(state.connections, provider.name, new_conn_pid)
              new_state = %{state | connections: new_connections}
              {:ok, new_conn_pid, new_state}

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end

  defp create_webrtc_stream(stream, tool_name, provider) do
    Stream.with_index(stream, 0)
    |> Stream.map(fn {chunk, index} ->
      case chunk do
        %{type: :stream, data: data} ->
          %{
            type: :stream_chunk,
            data: data,
            metadata: %{
              "sequence" => index,
              "tool" => tool_name,
              "provider" => provider.name,
              "transport" => "webrtc",
              "timestamp" => System.system_time(:millisecond)
            }
          }

        %{type: :result, data: data} ->
          %{
            type: :stream_result,
            data: data,
            metadata: %{
              "tool" => tool_name,
              "provider" => provider.name,
              "transport" => "webrtc",
              "timestamp" => System.system_time(:millisecond)
            }
          }

        %{type: :error, error: error} ->
          %{
            type: :stream_error,
            error: error,
            metadata: %{
              "tool" => tool_name,
              "provider" => provider.name,
              "transport" => "webrtc",
              "timestamp" => System.system_time(:millisecond)
            }
          }

        _ ->
          %{
            type: :stream_chunk,
            data: chunk,
            metadata: %{
              "sequence" => index,
              "tool" => tool_name,
              "provider" => provider.name,
              "transport" => "webrtc",
              "timestamp" => System.system_time(:millisecond)
            }
          }
      end
    end)
  end

  defp default_ice_servers do
    [
      %{
        urls: ["stun:stun.l.google.com:19302"]
      },
      %{
        urls: ["stun:stun1.l.google.com:19302"]
      }
    ]
  end
end
