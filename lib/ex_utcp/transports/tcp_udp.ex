defmodule ExUtcp.Transports.TcpUdp do
  @moduledoc """
  TCP/UDP Transport implementation for low-level network protocols.

  This transport supports both TCP and UDP protocols for direct network communication.
  It provides connection management, message serialization, and error handling.
  """

  use GenServer
  use ExUtcp.Transports.Behaviour

  alias ExUtcp.Transports.TcpUdp.{Connection, Pool}

  defstruct [
    :connection_pool,
    :retry_config,
    :connection_timeout,
    :providers
  ]

  def new(opts \\ []) do
    retry_config =
      Keyword.get(opts, :retry_config, %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2})

    %__MODULE__{
      connection_pool: nil,
      retry_config: retry_config,
      connection_timeout: Keyword.get(opts, :connection_timeout, 30_000),
      providers: %{}
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl ExUtcp.Transports.Behaviour
  def transport_name, do: "tcp_udp"

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming?, do: true

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :tcp -> register_tcp_provider(provider)
      :udp -> register_udp_provider(provider)
      _ -> {:error, "TCP/UDP transport can only be used with TCP or UDP providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(provider) do
    GenServer.call(__MODULE__, {:deregister_tool_provider, provider})
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    GenServer.call(__MODULE__, {:call_tool, tool_name, args, provider})
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(tool_name, args, provider) do
    GenServer.call(__MODULE__, {:call_tool_stream, tool_name, args, provider})
  end

  @impl ExUtcp.Transports.Behaviour
  def close do
    GenServer.call(__MODULE__, :close)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    connection_timeout = Keyword.get(opts, :connection_timeout, 30_000)
    retry_config = %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2}

    state = %__MODULE__{
      connection_pool: nil,
      retry_config: retry_config,
      connection_timeout: connection_timeout,
      providers: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_tool_provider, provider}, _from, state) do
    case provider.type do
      :tcp ->
        register_tcp_provider(provider, state)

      :udp ->
        register_udp_provider(provider, state)

      _ ->
        {:reply, {:error, "TCP/UDP transport can only be used with TCP or UDP providers"}, state}
    end
  end

  @impl GenServer
  def handle_call({:deregister_tool_provider, provider}, _from, state) do
    new_providers = Map.delete(state.providers, provider.name)
    new_state = %{state | providers: new_providers}
    {:reply, :ok, new_state}
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
  def handle_call(:close, _from, state) do
    if state.connection_pool do
      Pool.close_all_connections(state.connection_pool)
    end

    {:reply, :ok, state}
  end

  # Private functions

  defp register_tcp_provider(provider) do
    GenServer.call(__MODULE__, {:register_tool_provider, provider})
  end

  defp register_udp_provider(provider) do
    GenServer.call(__MODULE__, {:register_tool_provider, provider})
  end

  defp register_tcp_provider(provider, state) do
    case validate_tcp_provider(provider) do
      :ok ->
        new_providers = Map.put(state.providers, provider.name, provider)
        new_state = %{state | providers: new_providers}
        {:reply, {:ok, []}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp register_udp_provider(provider, state) do
    case validate_udp_provider(provider) do
      :ok ->
        new_providers = Map.put(state.providers, provider.name, provider)
        new_state = %{state | providers: new_providers}
        {:reply, {:ok, []}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp validate_tcp_provider(provider) do
    required_fields = [:name, :host, :port, :protocol]

    case Enum.find(required_fields, &(not Map.has_key?(provider, &1))) do
      nil -> :ok
      field -> {:error, "TCP provider missing required field: :#{field}"}
    end
  end

  defp validate_udp_provider(provider) do
    required_fields = [:name, :host, :port, :protocol]

    case Enum.find(required_fields, &(not Map.has_key?(provider, &1))) do
      nil -> :ok
      field -> {:error, "UDP provider missing required field: :#{field}"}
    end
  end

  defp execute_tool_call(tool_name, args, provider, state) do
    with_retry(
      fn ->
        try do
          case get_or_create_connection(provider, state) do
            {:ok, conn} ->
              case Connection.call_tool(conn, tool_name, args, state.connection_timeout) do
                {:ok, result} -> {:ok, result}
                {:error, reason} -> {:error, "Failed to call tool: #{inspect(reason)}"}
              end

            {:error, reason} ->
              {:error, "Failed to get connection: #{inspect(reason)}"}
          end
        catch
          :exit, reason -> {:error, "Connection failed: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp execute_tool_stream(tool_name, args, provider, state) do
    with_retry(
      fn ->
        try do
          case get_or_create_connection(provider, state) do
            {:ok, conn} ->
              case Connection.call_tool_stream(conn, tool_name, args, state.connection_timeout) do
                {:ok, stream} ->
                  # Enhance the stream with proper TCP/UDP streaming metadata
                  enhanced_stream = create_tcp_udp_stream(stream, tool_name, provider)

                  {:ok,
                   %{
                     type: :stream,
                     data: enhanced_stream,
                     metadata: %{
                       "transport" => "tcp_udp",
                       "tool" => tool_name,
                       "protocol" => provider.protocol
                     }
                   }}

                {:error, reason} ->
                  {:error, "Failed to call tool stream: #{inspect(reason)}"}
              end

            {:error, reason} ->
              {:error, "Failed to get connection: #{inspect(reason)}"}
          end
        catch
          :exit, reason -> {:error, "Connection failed: #{inspect(reason)}"}
        end
      end,
      state.retry_config
    )
  end

  defp create_tcp_udp_stream(stream, tool_name, provider) do
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
              "protocol" => provider.protocol
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
              "provider" => provider.name,
              "protocol" => provider.protocol
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
      end
    end)
  end

  defp with_retry(fun, retry_config) do
    max_retries = retry_config.max_retries
    retry_delay = retry_config.retry_delay
    backoff_multiplier = retry_config.backoff_multiplier

    with_retry_impl(fun, 0, max_retries, retry_delay, backoff_multiplier)
  end

  defp with_retry_impl(_fun, current_retry, max_retries, _retry_delay, _backoff_multiplier)
       when current_retry >= max_retries do
    {:error, "Max retries exceeded"}
  end

  defp with_retry_impl(fun, current_retry, max_retries, retry_delay, backoff_multiplier) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when current_retry < max_retries ->
        delay = (retry_delay * :math.pow(backoff_multiplier, current_retry)) |> round()
        Process.sleep(delay)
        with_retry_impl(fun, current_retry + 1, max_retries, retry_delay, backoff_multiplier)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_or_create_connection(provider, _state) do
    # Use mocked connection in test mode, real connection otherwise
    connection_module = Application.get_env(:ex_utcp, :tcp_udp_connection_behaviour, Connection)

    case connection_module.start_link(provider) do
      {:ok, conn_pid} -> {:ok, conn_pid}
      {:error, reason} -> {:error, "Failed to create connection: #{inspect(reason)}"}
    end
  end
end
