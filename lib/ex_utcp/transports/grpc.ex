defmodule ExUtcp.Transports.Grpc do
  @moduledoc """
  Production-ready gRPC transport implementation for UTCP.

  This transport handles gRPC-based tool providers with:
  - Real gRPC connections using Protocol Buffers
  - Connection pooling and lifecycle management
  - Authentication support (API Key, Basic, OAuth2)
  - Error recovery with retry logic
  - gNMI integration for network management
  - High-performance streaming capabilities
  """

  use ExUtcp.Transports.Behaviour
  use GenServer

  alias ExUtcp.Transports.Grpc.{Pool, Connection, Gnmi}

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
  Creates a new gRPC transport.
  """
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts \\ []) do
    %__MODULE__{
      logger: Keyword.get(opts, :logger, &Logger.info/1),
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      pool_opts: Keyword.get(opts, :pool_opts, []),
      retry_config: %{
        max_retries: Keyword.get(opts, :max_retries, 3),
        retry_delay: Keyword.get(opts, :retry_delay, 1000),
        backoff_multiplier: Keyword.get(opts, :backoff_multiplier, 2)
      },
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 1000)
    }
  end

  @doc """
  Starts the gRPC transport GenServer.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :grpc ->
        case GenServer.call(__MODULE__, {:register_tool_provider, provider}) do
          {:ok, tools} -> {:ok, tools}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "gRPC transport can only be used with gRPC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(provider) do
    case provider.type do
      :grpc ->
        GenServer.call(__MODULE__, {:deregister_tool_provider, provider})

      _ ->
        {:error, "gRPC transport can only be used with gRPC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    case provider.type do
      :grpc ->
        case GenServer.call(__MODULE__, {:call_tool, tool_name, args, provider}) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "gRPC transport can only be used with gRPC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(tool_name, args, provider) do
    case provider.type do
      :grpc ->
        case GenServer.call(__MODULE__, {:call_tool_stream, tool_name, args, provider}) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "gRPC transport can only be used with gRPC providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def close do
    GenServer.call(__MODULE__, :close)
  end

  @impl ExUtcp.Transports.Behaviour
  def transport_name do
    "grpc"
  end

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming? do
    true
  end

  @doc """
  Performs a gNMI Get operation.
  """
  @spec gnmi_get(pid(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def gnmi_get(provider, paths, opts \\ []) do
    case GenServer.call(__MODULE__, {:gnmi_get, provider, paths, opts}) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs a gNMI Set operation.
  """
  @spec gnmi_set(pid(), [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def gnmi_set(provider, updates, opts \\ []) do
    case GenServer.call(__MODULE__, {:gnmi_set, provider, updates, opts}) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs a gNMI Subscribe operation.
  """
  @spec gnmi_subscribe(pid(), [String.t()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def gnmi_subscribe(provider, paths, opts \\ []) do
    case GenServer.call(__MODULE__, {:gnmi_subscribe, provider, paths, opts}) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = new(opts)

    # Start the connection pool
    case Pool.start_link(state.pool_opts) do
      {:ok, _pool_pid} ->
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:register_tool_provider, provider}, _from, state) do
    case discover_tools(provider, state) do
      {:ok, tools} -> {:reply, {:ok, tools}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:deregister_tool_provider, _provider}, _from, state) do
    # For now, just return ok. In a real implementation, we might want to
    # close the specific connection or clean up resources.
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, provider}, _from, state) do
    case execute_tool_call(tool_name, args, provider, state) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, provider}, _from, state) do
    case execute_tool_stream(tool_name, args, provider, state) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:gnmi_get, provider, paths, opts}, _from, state) do
    case get_connection_and_execute(
           provider,
           fn conn ->
             Gnmi.get(conn, paths, opts)
           end,
           state
         ) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:gnmi_set, provider, updates, opts}, _from, state) do
    case get_connection_and_execute(
           provider,
           fn conn ->
             Gnmi.set(conn, updates, opts)
           end,
           state
         ) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:gnmi_subscribe, provider, paths, opts}, _from, state) do
    case get_connection_and_execute(
           provider,
           fn conn ->
             Gnmi.subscribe(conn, paths, opts)
           end,
           state
         ) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    Pool.close_all_connections()
    {:reply, :ok, state}
  end

  # Private functions

  defp discover_tools(provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.get_manual(conn, state.connection_timeout) do
              {:ok, tools} -> {:ok, tools}
              {:error, reason} -> {:error, "Failed to discover tools: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp execute_tool_call(tool_name, args, provider, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            case Connection.call_tool(conn, tool_name, args, state.connection_timeout) do
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
            case Connection.call_tool_stream(conn, tool_name, args, state.connection_timeout) do
              {:ok, results} ->
                # Enhance the stream with proper gRPC streaming metadata
                enhanced_stream = create_grpc_stream(results, tool_name, provider)

                {:ok,
                 %{
                   type: :stream,
                   data: enhanced_stream,
                   metadata: %{"transport" => "grpc", "tool" => tool_name, "protocol" => "grpc"}
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

  defp create_grpc_stream(results, tool_name, provider) do
    Stream.with_index(results, 0)
    |> Stream.map(fn {result, index} ->
      %{
        data: result,
        metadata: %{
          "sequence" => index,
          "timestamp" => System.monotonic_time(:millisecond),
          "tool" => tool_name,
          "provider" => provider.name,
          "protocol" => "grpc",
          "service" => provider.service_name
        },
        timestamp: System.monotonic_time(:millisecond),
        sequence: index
      }
    end)
  end

  defp get_connection_and_execute(provider, fun, state) do
    with_retry(
      fn ->
        case Pool.get_connection(provider) do
          {:ok, conn} ->
            fun.(conn)

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp with_retry(fun, retry_config, attempt \\ 0) do
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
