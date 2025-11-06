defmodule ExUtcp.Transports.WebSocket do
  @moduledoc """
  WebSocket transport implementation for UTCP.

  This transport handles WebSocket-based tool providers, supporting real-time
  bidirectional communication for tool discovery and execution.
  """

  use ExUtcp.Transports.Behaviour
  use GenServer

  alias ExUtcp.Auth
  alias ExUtcp.Transports.WebSocket.Connection

  require Logger

  defstruct [
    :logger,
    :connection_timeout,
    :connection_pool,
    :retry_config,
    :max_retries,
    :retry_delay
  ]

  @doc """
  Creates a new WebSocket transport.
  """
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts \\ []) do
    %__MODULE__{
      logger: Keyword.get(opts, :logger, &Logger.info/1),
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      connection_pool: %{},
      retry_config: %{
        max_retries: Keyword.get(opts, :max_retries, 3),
        retry_delay: Keyword.get(opts, :retry_delay, 1000),
        backoff_multiplier: Keyword.get(opts, :backoff_multiplier, 2)
      },
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 1000)
    }
  end

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :websocket -> discover_tools(provider)
      _ -> {:error, "WebSocket transport can only be used with WebSocket providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(provider) do
    case provider.type do
      :websocket -> close_connection(provider)
      _ -> {:error, "WebSocket transport can only be used with WebSocket providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    case provider.type do
      :websocket -> execute_tool_call(tool_name, args, provider)
      _ -> {:error, "WebSocket transport can only be used with WebSocket providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(tool_name, args, provider) do
    case provider.type do
      :websocket -> execute_tool_stream(tool_name, args, provider)
      _ -> {:error, "WebSocket transport can only be used with WebSocket providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def close do
    :ok
  end

  @impl ExUtcp.Transports.Behaviour
  def transport_name do
    "websocket"
  end

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming? do
    true
  end

  # GenServer callbacks for connection management

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    state = new(opts)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_connection, provider}, _from, state) do
    case get_or_create_connection(provider, state) do
      {:ok, conn, new_state} -> {:reply, {:ok, conn}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:close_connection, provider}, _from, state) do
    new_state = close_connection_for_provider(provider, state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:close_all, _from, state) do
    new_state = close_all_connections(state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info({:websocket, _conn, {:text, data}}, state) do
    # Handle incoming WebSocket messages
    Logger.debug("Received WebSocket message: #{data}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket, conn, :close}, state) do
    # Handle WebSocket connection close
    Logger.info("WebSocket connection closed: #{inspect(conn)}")
    new_state = remove_connection_from_pool(conn, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:websocket, _conn, {:error, reason}}, state) do
    # Handle WebSocket errors
    Logger.error("WebSocket error: #{inspect(reason)}")
    {:noreply, state}
  end

  # Private functions

  defp discover_tools(provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        with {:ok, conn} <- get_or_create_connection(provider),
             {:ok, tools} <- request_manual(conn, provider) do
          {:ok, tools}
        else
          {:error, reason} -> {:error, "Failed to discover tools: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_call(tool_name, args, provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        with {:ok, conn} <- get_or_create_connection(provider),
             {:ok, result} <- send_tool_request(conn, tool_name, args, provider) do
          {:ok, result}
        else
          {:error, reason} -> {:error, "Failed to execute tool: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_stream(tool_name, args, provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        with {:ok, conn} <- get_or_create_connection(provider),
             {:ok, stream_result} <- send_tool_stream_request(conn, tool_name, args, provider) do
          # Enhance the stream with proper WebSocket streaming metadata
          enhanced_stream = create_websocket_stream(stream_result, tool_name, provider)

          {:ok,
           %{
             type: :stream,
             data: enhanced_stream,
             metadata: %{"transport" => "websocket", "tool" => tool_name, "protocol" => "ws"}
           }}
        else
          {:error, reason} -> {:error, "Failed to execute tool stream: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp create_websocket_stream(stream, tool_name, provider) do
    Stream.with_index(stream, 0)
    |> Stream.map(fn {chunk, index} ->
      case chunk do
        %{"type" => "stream_end"} ->
          %{type: :end, metadata: %{"sequence" => index, "tool" => tool_name}}

        %{"type" => "error", "message" => error} ->
          %{type: :error, error: error, code: 500, metadata: %{"sequence" => index}}

        data ->
          %{
            data: data,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider.name,
              "protocol" => "ws"
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
      end
    end)
  end

  defp get_or_create_connection(provider) do
    case GenServer.call(__MODULE__, {:get_connection, provider}) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_connection(provider, state) do
    connection_key = build_connection_key(provider)

    case Map.get(state.connection_pool, connection_key) do
      nil ->
        # Create new connection
        case establish_connection(provider, state) do
          {:ok, conn} ->
            new_pool = Map.put(state.connection_pool, connection_key, conn)
            new_state = %{state | connection_pool: new_pool}
            {:ok, conn, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      conn ->
        # Use existing connection
        {:ok, conn, state}
    end
  end

  defp establish_connection(provider, state) do
    headers = build_headers(provider)
    headers = Auth.apply_to_headers(provider.auth, headers)

    # Add WebSocket protocol if specified
    headers =
      if provider.protocol do
        Map.put(headers, "Sec-WebSocket-Protocol", provider.protocol)
      else
        headers
      end

    # Convert headers to the format expected by websockex
    ws_headers = Enum.map(headers, fn {k, v} -> {String.to_atom(k), v} end)

    opts = [
      extra_headers: ws_headers,
      timeout: state.connection_timeout,
      transport_pid: self(),
      ping_interval: 30_000
    ]

    case Connection.start_link(provider.url, provider, opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, "Failed to connect to WebSocket: #{inspect(reason)}"}
    end
  end

  defp build_connection_key(provider) do
    "#{provider.url}:#{provider.name}"
  end

  defp build_headers(provider) do
    base_headers = %{
      "User-Agent" => "ExUtcp/0.2.0",
      "Accept" => "application/json"
    }

    Map.merge(base_headers, provider.headers)
  end

  defp request_manual(conn, provider) do
    case Connection.send_message(conn, "manual") do
      :ok ->
        case Connection.get_next_message(conn, 5_000) do
          {:ok, response} -> parse_manual_response(response, provider)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to send manual request: #{inspect(reason)}"}
    end
  end

  defp send_tool_request(conn, _tool_name, args, _provider) do
    case Jason.encode(args) do
      {:ok, json_data} ->
        case Connection.send_message(conn, json_data) do
          :ok ->
            case Connection.get_next_message(conn, 30_000) do
              {:ok, response} -> parse_tool_response(response)
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, "Failed to send tool request: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to encode arguments: #{inspect(reason)}"}
    end
  end

  defp send_tool_stream_request(conn, _tool_name, args, _provider) do
    case Jason.encode(args) do
      {:ok, json_data} ->
        case Connection.send_message(conn, json_data) do
          :ok ->
            # For streaming, we collect all messages until connection closes
            collect_stream_messages(conn, [])

          {:error, reason} ->
            {:error, "Failed to send tool request: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to encode arguments: #{inspect(reason)}"}
    end
  end

  defp collect_stream_messages(conn, acc) do
    # Get all available messages from the connection
    messages = Connection.get_all_messages(conn)

    case messages do
      [] ->
        # No messages available, wait a bit and try again
        Process.sleep(100)
        collect_stream_messages(conn, acc)

      msgs ->
        # Process all messages
        decoded_messages =
          Enum.map(msgs, fn msg ->
            case Jason.decode(msg) do
              {:ok, decoded} -> decoded
              {:error, _} -> msg
            end
          end)

        new_acc = Enum.reverse(decoded_messages, acc)

        # Check if we should continue collecting or return
        if length(msgs) < 10 do
          # Few messages, might be done
          {:ok, %{type: :stream, data: Enum.reverse(new_acc)}}
        else
          # More messages available, continue collecting
          collect_stream_messages(conn, new_acc)
        end
    end
  end

  defp parse_manual_response(response, provider) do
    case Jason.decode(response) do
      {:ok, data} ->
        case data do
          %{"tools" => tools} when is_list(tools) ->
            normalized_tools = Enum.map(tools, &normalize_tool(&1, provider))
            {:ok, normalized_tools}

          _ ->
            {:ok, []}
        end

      {:error, reason} ->
        {:error, "Failed to parse manual response: #{inspect(reason)}"}
    end
  end

  defp parse_tool_response(response) do
    case Jason.decode(response) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "Failed to parse tool response: #{inspect(reason)}"}
    end
  end

  defp normalize_tool(tool_data, provider) do
    ExUtcp.Tools.new_tool(
      name: Map.get(tool_data, "name", ""),
      description: Map.get(tool_data, "description", ""),
      inputs: parse_schema(Map.get(tool_data, "inputs", %{})),
      outputs: parse_schema(Map.get(tool_data, "outputs", %{})),
      tags: Map.get(tool_data, "tags", []),
      average_response_size: Map.get(tool_data, "average_response_size"),
      provider: provider
    )
  end

  defp parse_schema(schema_data) do
    ExUtcp.Tools.new_schema(
      type: Map.get(schema_data, "type", "object"),
      properties: Map.get(schema_data, "properties", %{}),
      required: Map.get(schema_data, "required", []),
      description: Map.get(schema_data, "description", ""),
      title: Map.get(schema_data, "title", ""),
      items: Map.get(schema_data, "items", %{}),
      enum: Map.get(schema_data, "enum", []),
      minimum: Map.get(schema_data, "minimum"),
      maximum: Map.get(schema_data, "maximum"),
      format: Map.get(schema_data, "format", "")
    )
  end

  defp close_connection(provider) do
    GenServer.call(__MODULE__, {:close_connection, provider})
  end

  defp close_connection_for_provider(provider, state) do
    connection_key = build_connection_key(provider)

    case Map.get(state.connection_pool, connection_key) do
      nil ->
        state

      conn ->
        Connection.close(conn)
        new_pool = Map.delete(state.connection_pool, connection_key)
        %{state | connection_pool: new_pool}
    end
  end

  defp close_all_connections(state) do
    Enum.each(state.connection_pool, fn {_key, conn} ->
      Connection.close(conn)
    end)

    %{state | connection_pool: %{}}
  end

  defp remove_connection_from_pool(conn, state) do
    # Find and remove the connection from the pool
    new_pool =
      Enum.reject(state.connection_pool, fn {_key, pool_conn} ->
        pool_conn == conn
      end)
      |> Map.new()

    %{state | connection_pool: new_pool}
  end

  # Retry logic with exponential backoff
  defp with_retry(fun, retry_config) do
    with_retry(fun, retry_config, 0)
  end

  defp with_retry(fun, retry_config, attempt) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when attempt < retry_config.max_retries ->
        delay = retry_config.retry_delay * :math.pow(retry_config.backoff_multiplier, attempt)
        :timer.sleep(round(delay))
        with_retry(fun, retry_config, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
