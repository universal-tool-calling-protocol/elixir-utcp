defmodule ExUtcp.Transports.WebSocket.Testable do
  @moduledoc """
  Testable version of WebSocket transport that can use mocks.
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
    :retry_delay,
    :genserver_module,
    :connection_module
  ]

  @doc """
  Creates a new testable WebSocket transport.
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
      retry_delay: Keyword.get(opts, :retry_delay, 1000),
      genserver_module: Keyword.get(opts, :genserver_module, __MODULE__),
      connection_module: Keyword.get(opts, :connection_module, Connection)
    }
  end

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :websocket -> discover_tools(provider)
      _ -> {:error, "WebSocket transport can only be used with WebSocket providers"}
    end
  end

  def register_tool_provider(transport, provider) do
    case provider.type do
      :websocket -> discover_tools(transport, provider)
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

  def deregister_tool_provider(transport, provider) do
    case provider.type do
      :websocket -> close_connection(transport, provider)
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

  def call_tool(transport, tool_name, args, provider) do
    case provider.type do
      :websocket -> execute_tool_call(transport, tool_name, args, provider)
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

  def call_tool_stream(transport, tool_name, args, provider) do
    case provider.type do
      :websocket -> execute_tool_stream(transport, tool_name, args, provider)
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
    genserver_module = Keyword.get(opts, :genserver_module, __MODULE__)
    GenServer.start_link(genserver_module, opts, name: __MODULE__)
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

  defp discover_tools(transport, provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        case get_or_create_connection(transport, provider) do
          {:ok, conn, _new_transport} ->
            case request_manual(conn, provider) do
              {:ok, tools} -> {:ok, tools}
              {:error, reason} -> {:error, "Failed to discover tools: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to discover tools: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_call(tool_name, args, provider) do
    # Create a default transport for this call
    transport = new()
    execute_tool_call(transport, tool_name, args, provider)
  end

  defp execute_tool_call(transport, tool_name, args, provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        case get_or_create_connection(transport, provider) do
          {:ok, conn, _new_transport} ->
            case send_tool_request(transport, conn, tool_name, args, provider) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, "Failed to execute tool: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to execute tool: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_stream(tool_name, args, provider) do
    # Create a default transport for this call
    transport = new()
    execute_tool_stream(transport, tool_name, args, provider)
  end

  defp execute_tool_stream(transport, tool_name, args, provider) do
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    with_retry(
      fn ->
        case get_or_create_connection(transport, provider) do
          {:ok, conn, _new_transport} ->
            case send_tool_stream_request(transport, conn, tool_name, args, provider) do
              {:ok, stream_result} -> {:ok, stream_result}
              {:error, reason} -> {:error, "Failed to execute tool stream: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to execute tool stream: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp get_or_create_connection(provider) do
    case GenServer.call(__MODULE__, {:get_connection, provider}) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_connection(transport, provider) do
    connection_key = build_connection_key(provider)

    case Map.get(transport.connection_pool, connection_key) do
      nil ->
        # For testing, simulate getting a connection using the injected mock
        case transport.connection_module do
          Connection ->
            # Real connection - use the actual implementation
            case establish_connection_for_transport(transport, provider) do
              {:ok, conn} ->
                new_pool = Map.put(transport.connection_pool, connection_key, conn)
                new_transport = %{transport | connection_pool: new_pool}
                {:ok, conn, new_transport}

              {:error, reason} ->
                {:error, reason}
            end

          _ ->
            # Mock connection - return mock
            {:ok, :mock_connection, transport}
        end

      conn ->
        # Use existing connection
        {:ok, conn, transport}
    end
  end

  defp establish_connection_for_transport(transport, provider) do
    headers = build_headers(provider)
    headers = Auth.apply_to_headers(Map.get(provider, :auth), headers)

    # Add WebSocket protocol if specified
    headers =
      if Map.get(provider, :protocol) do
        Map.put(headers, "Sec-WebSocket-Protocol", Map.get(provider, :protocol))
      else
        headers
      end

    # Convert headers to the format expected by websockex
    # Use existing atoms only to prevent DOS attacks
    ws_headers = Enum.map(headers, fn {k, v} -> {safe_string_to_atom(k), v} end)

    _opts = [
      extra_headers: ws_headers,
      timeout: transport.connection_timeout,
      transport_pid: self(),
      ping_interval: 30_000
    ]

    connection_module = transport.connection_module || Connection

    case connection_module.start_link(provider) do
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

    Map.merge(base_headers, Map.get(provider, :headers, %{}))
  end

  defp request_manual(conn, provider) do
    # For testing, we'll simulate the manual request
    # In a real implementation, this would use the connection module
    case conn do
      :mock_connection ->
        # Mock response for testing
        {:ok, [%{"name" => "test_tool", "description" => "A test tool"}]}

      _ ->
        # Real connection - use the actual implementation
        connection_module = Connection

        case connection_module.send_message(conn, "manual") do
          :ok ->
            case connection_module.get_next_message(conn, 5_000) do
              {:ok, response} -> parse_manual_response(response, provider)
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, "Failed to send manual request: #{inspect(reason)}"}
        end
    end
  end

  defp send_tool_request(transport, conn, tool_name, args, _provider) do
    case conn do
      :mock_connection ->
        # Use the injected mock module
        connection_module = transport.connection_module || Connection

        case connection_module.call_tool(conn, tool_name, args, []) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        # Real connection - use the actual implementation
        connection_module = Connection

        case Jason.encode(args) do
          {:ok, json_data} ->
            case connection_module.send_message(conn, json_data) do
              :ok ->
                case connection_module.get_next_message(conn, 30_000) do
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
  end

  defp send_tool_stream_request(transport, conn, _tool_name, args, _provider) do
    case conn do
      :mock_connection ->
        # Use the injected mock module
        connection_module = transport.connection_module || Connection

        case connection_module.call_tool_stream(conn, "stream_tool", args, []) do
          {:ok, stream} -> {:ok, stream}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        # Real connection - use the actual implementation
        connection_module = Connection

        case Jason.encode(args) do
          {:ok, json_data} ->
            case connection_module.send_message(conn, json_data) do
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
  end

  defp collect_stream_messages(conn, acc) do
    # Get all available messages from the connection
    connection_module = Connection
    messages = connection_module.get_all_messages(conn)

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

  defp close_connection(transport, provider) do
    connection_key = build_connection_key(provider)
    connection_module = Application.get_env(:ex_utcp, :connection_module, Connection)

    case Map.get(transport.connection_pool, connection_key) do
      nil ->
        :ok

      conn ->
        connection_module.close(conn)
        :ok
    end
  end

  defp close_connection_for_provider(provider, state) do
    connection_key = build_connection_key(provider)
    connection_module = Application.get_env(:ex_utcp, :connection_module, Connection)

    case Map.get(state.connection_pool, connection_key) do
      nil ->
        state

      conn ->
        connection_module.close(conn)
        new_pool = Map.delete(state.connection_pool, connection_key)
        %{state | connection_pool: new_pool}
    end
  end

  defp close_all_connections(state) do
    connection_module = Application.get_env(:ex_utcp, :connection_module, Connection)

    Enum.each(state.connection_pool, fn {_key, conn} ->
      connection_module.close(conn)
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

  # Additional functions for testing
  def send_message(transport, message, provider) do
    case get_or_create_connection(transport, provider) do
      {:ok, conn, _new_transport} ->
        connection_module = transport.connection_module || Connection
        connection_module.send_message(conn, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_next_message(transport, provider) do
    case get_or_create_connection(transport, provider) do
      {:ok, conn, _new_transport} ->
        connection_module = transport.connection_module || Connection
        connection_module.get_next_message(conn, 5000)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def close(_transport) do
    :ok
  end

  # Safe conversion to atom - only converts if atom already exists
  # Falls back to string if atom doesn't exist to prevent atom table exhaustion
  defp safe_string_to_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      # Try lowercase version
      try do
        String.to_existing_atom(String.downcase(string))
      rescue
        ArgumentError -> string
      end
  end
end
