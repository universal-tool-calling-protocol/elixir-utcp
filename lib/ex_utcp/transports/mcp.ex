defmodule ExUtcp.Transports.Mcp do
  @moduledoc """
  Production-ready MCP (Model Context Protocol) transport implementation for UTCP.

  MCP is a protocol for connecting AI assistants to external data sources and tools.
  This transport supports JSON-RPC 2.0 communication over HTTP/HTTPS with SSE support.
  """

  use ExUtcp.Transports.Behaviour
  use GenServer

  alias ExUtcp.Transports.Mcp.Connection
  alias ExUtcp.Transports.Mcp.Pool

  require Logger

  defstruct [
    :logger,
    :connection_timeout,
    :pool_opts,
    :retry_config,
    :max_retries,
    :retry_delay
  ]

  @doc """
  Creates a new MCP transport with the given options.
  """
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts \\ []) do
    %__MODULE__{
      logger: Keyword.get(opts, :logger, &Logger.info/1),
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      pool_opts: Keyword.get(opts, :pool_opts, []),
      retry_config:
        Keyword.get(opts, :retry_config, %{
          max_retries: 3,
          base_delay: 1000,
          max_delay: 10_000,
          backoff_multiplier: 2
        }),
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 1000)
    }
  end

  @doc """
  Starts the MCP transport GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the transport name.
  """
  @spec transport_name() :: String.t()
  @impl true
  def transport_name, do: "mcp"

  @doc """
  Returns whether this transport supports streaming.
  """
  @spec supports_streaming?() :: boolean()
  @impl true
  def supports_streaming?, do: true

  @doc """
  Registers a tool provider with the MCP transport.
  """
  @spec register_tool_provider(ExUtcp.Types.mcp_provider()) :: :ok | {:error, String.t()}
  @impl true
  def register_tool_provider(provider) do
    case provider.type do
      :mcp ->
        case GenServer.call(__MODULE__, {:register_tool_provider, provider}) do
          {:ok, tools} -> {:ok, tools}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "MCP transport can only be used with MCP providers"}
    end
  end

  @doc """
  Deregisters a tool provider from the MCP transport.
  """
  @spec deregister_tool_provider(ExUtcp.Types.mcp_provider()) :: :ok | {:error, String.t()}
  @impl true
  def deregister_tool_provider(provider) do
    case provider.type do
      :mcp ->
        GenServer.call(__MODULE__, {:deregister_tool_provider, provider})

      _ ->
        {:error, "MCP transport can only be used with MCP providers"}
    end
  end

  @doc """
  Calls a tool using the MCP transport.
  """
  @spec call_tool(String.t(), map(), ExUtcp.Types.mcp_provider()) :: ExUtcp.Types.call_result()
  @impl true
  def call_tool(tool_name, args, provider) do
    GenServer.call(__MODULE__, {:call_tool, tool_name, args, provider})
  end

  @doc """
  Calls a tool with streaming support using the MCP transport.
  """
  @spec call_tool_stream(String.t(), map(), ExUtcp.Types.mcp_provider()) ::
          ExUtcp.Types.call_result()
  @impl true
  def call_tool_stream(tool_name, args, provider) do
    GenServer.call(__MODULE__, {:call_tool_stream, tool_name, args, provider})
  end

  @doc """
  Sends a JSON-RPC request to the MCP server.
  """
  @spec send_request(String.t(), map(), ExUtcp.Types.mcp_provider()) :: ExUtcp.Types.call_result()
  def send_request(method, params, provider) do
    GenServer.call(__MODULE__, {:send_request, method, params, provider})
  end

  @doc """
  Sends a JSON-RPC notification to the MCP server.
  """
  @spec send_notification(String.t(), map(), ExUtcp.Types.mcp_provider()) ::
          :ok | {:error, String.t()}
  def send_notification(method, params, provider) do
    GenServer.call(__MODULE__, {:send_notification, method, params, provider})
  end

  @doc """
  Closes the MCP transport.
  """
  @spec close() :: :ok
  @impl true
  def close do
    GenServer.call(__MODULE__, :close)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = new(opts)

    case Pool.start_link(state.pool_opts) do
      {:ok, _pool_pid} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:register_tool_provider, provider}, _from, state) do
    case validate_provider(provider) do
      :ok ->
        Logger.info("MCP transport registered provider: #{provider.name}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:deregister_tool_provider, _provider}, _from, state) do
    Logger.info("MCP transport deregistered provider")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, provider}, _from, state) do
    result = execute_tool_call(tool_name, args, provider, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, provider}, _from, state) do
    result = execute_tool_stream(tool_name, args, provider, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:send_request, method, params, provider}, _from, state) do
    result = execute_request(method, params, provider, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:send_notification, method, params, provider}, _from, state) do
    result = execute_notification(method, params, provider, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    Pool.close_all_connections()
    {:reply, :ok, state}
  end

  # Private functions

  defp validate_provider(provider) do
    cond do
      provider.type != :mcp ->
        {:error, "Invalid provider type for MCP transport"}

      is_nil(provider.url) or provider.url == "" ->
        {:error, "MCP provider URL is required"}

      true ->
        :ok
    end
  end

  defp execute_tool_call(tool_name, args, provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.call_tool(conn, tool_name, args, timeout: state.connection_timeout) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, "Failed to call tool: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp execute_tool_stream(tool_name, args, provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.call_tool_stream(conn, tool_name, args, timeout: state.connection_timeout) do
              {:ok, stream} ->
                # Enhance the stream with proper MCP streaming metadata
                enhanced_stream = create_mcp_stream(stream, tool_name, provider)

                {:ok,
                 %{
                   type: :stream,
                   data: enhanced_stream,
                   metadata: %{
                     "transport" => "mcp",
                     "tool" => tool_name,
                     "protocol" => "json-rpc-2.0"
                   }
                 }}

              {:error, reason} ->
                {:error, "Failed to call tool stream: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp create_mcp_stream(stream, tool_name, provider) do
    Stream.with_index(stream, 0)
    |> Stream.map(fn {chunk, index} ->
      case chunk do
        %{type: :stream, data: data} ->
          %{
            data: data,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider.name,
              "protocol" => "json-rpc-2.0"
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }

        %{type: :error, error: error} ->
          %{type: :error, error: error, code: 500, metadata: %{"sequence" => index}}

        %{type: :end} ->
          %{type: :end, metadata: %{"sequence" => index}}

        other ->
          %{
            data: other,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider.name
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
      end
    end)
  end

  defp execute_request(method, params, provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.send_request(conn, method, params, timeout: state.connection_timeout) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, "Failed to send request: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp execute_notification(method, params, provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.send_notification(conn, method, params, timeout: state.connection_timeout) do
              :ok -> :ok
              {:error, reason} -> {:error, "Failed to send notification: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp with_retry(fun, retry_config) do
    max_retries = Map.get(retry_config, :max_retries, 3)
    base_delay = Map.get(retry_config, :base_delay, 1000)
    max_delay = Map.get(retry_config, :max_delay, 10_000)
    backoff_multiplier = Map.get(retry_config, :backoff_multiplier, 2)

    with_retry_impl(fun, 0, max_retries, base_delay, max_delay, backoff_multiplier)
  end

  defp with_retry_impl(fun, attempt, max_retries, _base_delay, _max_delay, _backoff_multiplier)
       when attempt >= max_retries do
    fun.()
  end

  defp with_retry_impl(fun, attempt, max_retries, base_delay, max_delay, backoff_multiplier) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when attempt < max_retries - 1 ->
        delay = min(base_delay * :math.pow(backoff_multiplier, attempt), max_delay)
        :timer.sleep(round(delay))
        with_retry_impl(fun, attempt + 1, max_retries, base_delay, max_delay, backoff_multiplier)

      result ->
        result
    end
  end
end
