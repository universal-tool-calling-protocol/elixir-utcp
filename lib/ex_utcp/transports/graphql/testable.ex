defmodule ExUtcp.Transports.Graphql.Testable do
  @moduledoc """
  Testable version of the GraphQL transport that allows injecting mock modules.
  """

  use GenServer

  alias ExUtcp.Transports.Graphql.{Schema, MockConnection}

  require Logger

  defstruct [
    :logger,
    :connection_timeout,
    :pool_opts,
    :retry_config,
    :max_retries,
    :retry_delay,
    # For testing GenServer calls
    :genserver_module,
    # For testing Connection calls
    :connection_module
  ]

  @doc """
  Creates a new testable GraphQL transport.
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
      retry_delay: Keyword.get(opts, :retry_delay, 1000),
      genserver_module: Keyword.get(opts, :genserver_module, GenServer),
      connection_module: Keyword.get(opts, :connection_module, MockConnection)
    }
  end

  @doc """
  Overloaded public functions that accept a transport struct as the first argument
  to allow direct manipulation of the transport state in tests.
  """
  @spec register_tool_provider(%__MODULE__{}, map()) :: {:ok, [map()]} | {:error, term()}
  def register_tool_provider(transport, provider) do
    case provider.type do
      :graphql ->
        case discover_tools(transport, provider) do
          {:ok, tools} -> {:ok, tools}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @spec deregister_tool_provider(%__MODULE__{}, map()) :: :ok | {:error, term()}
  def deregister_tool_provider(_transport, provider) do
    case provider.type do
      :graphql ->
        # For now, just return ok. In a real implementation, we might want to
        # close the specific connection or clean up resources.
        :ok

      _ ->
        {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @spec call_tool(%__MODULE__{}, String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def call_tool(transport, tool_name, args, provider) do
    case provider.type do
      :graphql ->
        case execute_tool_call(transport, tool_name, args, provider) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @spec call_tool_stream(%__MODULE__{}, String.t(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def call_tool_stream(transport, tool_name, args, provider) do
    case provider.type do
      :graphql ->
        case execute_tool_stream(transport, tool_name, args, provider) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @spec query(%__MODULE__{}, map(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def query(transport, provider, query_string, variables \\ %{}, opts \\ []) do
    case get_connection_and_execute(transport, provider, fn conn ->
           transport.connection_module.query(conn, query_string, variables, opts)
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec mutation(%__MODULE__{}, map(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def mutation(transport, provider, mutation_string, variables \\ %{}, opts \\ []) do
    case get_connection_and_execute(transport, provider, fn conn ->
           transport.connection_module.mutation(conn, mutation_string, variables, opts)
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec subscription(%__MODULE__{}, map(), String.t(), map(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def subscription(transport, provider, subscription_string, variables \\ %{}, opts \\ []) do
    case get_connection_and_execute(transport, provider, fn conn ->
           transport.connection_module.subscription(conn, subscription_string, variables, opts)
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec introspect_schema(%__MODULE__{}, map(), keyword()) :: {:ok, map()} | {:error, term()}
  def introspect_schema(transport, provider, opts \\ []) do
    case get_connection_and_execute(transport, provider, fn conn ->
           transport.connection_module.introspect_schema(conn, opts)
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp discover_tools(transport, provider) do
    retry_config =
      transport.retry_config || %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2.0}

    with_retry(
      fn ->
        case get_connection(transport, provider) do
          {:ok, conn} ->
            case transport.connection_module.introspect_schema(conn,
                   timeout: transport.connection_timeout
                 ) do
              {:ok, schema} ->
                tools = Schema.extract_tools(schema)
                {:ok, tools}

              {:error, reason} ->
                {:error, "Failed to discover tools: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_call(transport, tool_name, args, provider) do
    retry_config =
      transport.retry_config || %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2.0}

    with_retry(
      fn ->
        case get_connection(transport, provider) do
          {:ok, conn} ->
            # Convert tool call to GraphQL query
            case build_graphql_operation(tool_name, args) do
              {:query, query_string, variables} ->
                case transport.connection_module.query(conn, query_string, variables,
                       timeout: transport.connection_timeout
                     ) do
                  {:ok, result} -> {:ok, result}
                  {:error, reason} -> {:error, "Failed to execute query: #{inspect(reason)}"}
                end
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp execute_tool_stream(transport, tool_name, args, provider) do
    retry_config =
      transport.retry_config || %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2.0}

    with_retry(
      fn ->
        case get_connection(transport, provider) do
          {:ok, conn} ->
            # Convert tool stream to GraphQL subscription
            case build_graphql_subscription(tool_name, args) do
              {:subscription, subscription_string, variables} ->
                case transport.connection_module.subscription(
                       conn,
                       subscription_string,
                       variables,
                       timeout: transport.connection_timeout
                     ) do
                  {:ok, results} ->
                    {:ok, %{type: :stream, data: results}}

                  {:error, reason} ->
                    {:error, "Failed to execute subscription: #{inspect(reason)}"}
                end
            end

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp get_connection_and_execute(transport, provider, fun) do
    retry_config =
      transport.retry_config || %{max_retries: 3, retry_delay: 1000, backoff_multiplier: 2.0}

    with_retry(
      fn ->
        case get_connection(transport, provider) do
          {:ok, conn} ->
            fun.(conn)

          {:error, reason} ->
            {:error, "Failed to get connection: #{inspect(reason)}"}
        end
      end,
      retry_config
    )
  end

  defp get_connection(transport, _provider) do
    # For testing, we'll simulate getting a connection using the injected mock
    # In a real implementation, this would use the connection pool
    case transport.connection_module do
      MockConnection -> {:ok, :mock_connection}
      _ -> {:ok, :mock_connection}
    end
  end

  defp build_graphql_operation(tool_name, args) do
    # Simple implementation - in a real system, this would be more sophisticated
    # For now, we'll treat all tool calls as queries
    query_string = """
    query #{String.replace(tool_name, ".", "_")}($input: JSON!) {
      #{String.replace(tool_name, ".", "_")}(input: $input) {
        result
        success
        error
      }
    }
    """

    variables = %{"input" => args}
    {:query, query_string, variables}
  end

  defp build_graphql_subscription(tool_name, args) do
    # Simple implementation - in a real system, this would be more sophisticated
    subscription_string = """
    subscription #{String.replace(tool_name, ".", "_")}($input: JSON!) {
      #{String.replace(tool_name, ".", "_")}(input: $input) {
        data
        timestamp
      }
    }
    """

    variables = %{"input" => args}
    {:subscription, subscription_string, variables}
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

  # Implement ExUtcp.Transports.Behaviour callbacks
  @impl ExUtcp.Transports.Behaviour
  def transport_name, do: "graphql"

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming?, do: true

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    execute_tool_call(tool_name, args, provider, [])
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(tool_name, args, provider) do
    execute_tool_stream(tool_name, args, provider, [])
  end

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :graphql ->
        # Create a default transport for testing
        transport = new()

        case discover_tools(transport, provider) do
          {:ok, tools} -> {:ok, tools}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(provider) do
    case provider.type do
      :graphql -> :ok
      _ -> {:error, "GraphQL transport can only be used with GraphQL providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def close, do: :ok

  # Additional function for testing with transport parameter
  def close(_transport), do: :ok
end
