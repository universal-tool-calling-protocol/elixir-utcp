defmodule ExUtcp.Transports.Graphql.Connection do
  @moduledoc """
  Manages GraphQL connections with pooling and lifecycle management.
  """

  @behaviour ExUtcp.Transports.Graphql.ConnectionBehaviour

  use GenServer

  require Logger

  defstruct [
    :provider,
    :client,
    :connection_state,
    :last_used,
    :retry_count,
    :max_retries,
    :subscription_handles
  ]

  @type t :: %__MODULE__{
          provider: map(),
          client: Req.Request.t(),
          connection_state: :connecting | :connected | :disconnected | :error,
          last_used: DateTime.t(),
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer(),
          subscription_handles: %{String.t() => pid()}
        }

  @doc """
  Starts a new GraphQL connection process.
  """
  @spec start_link(map(), keyword()) :: {:ok, pid()} | {:error, term()}
  @impl true
  def start_link(provider, opts \\ []) do
    GenServer.start_link(__MODULE__, {provider, opts})
  end

  @doc """
  Executes a GraphQL query.
  """
  @spec query(pid(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @impl true
  def query(pid, query_string, variables \\ %{}, opts \\ []) do
    GenServer.call(pid, {:query, query_string, variables, opts})
  end

  @doc """
  Executes a GraphQL mutation.
  """
  @spec mutation(pid(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @impl true
  def mutation(pid, mutation_string, variables \\ %{}, opts \\ []) do
    GenServer.call(pid, {:mutation, mutation_string, variables, opts})
  end

  @doc """
  Executes a GraphQL subscription.
  """
  @spec subscription(pid(), String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @impl true
  def subscription(pid, subscription_string, variables \\ %{}, opts \\ []) do
    GenServer.call(pid, {:subscription, subscription_string, variables, opts})
  end

  @doc """
  Introspects the GraphQL schema.
  """
  @spec introspect_schema(pid(), keyword()) :: {:ok, map()} | {:error, term()}
  @impl true
  def introspect_schema(pid, opts \\ []) do
    GenServer.call(pid, {:introspect_schema, opts})
  end

  @doc """
  Closes the GraphQL connection.
  """
  @spec close(pid()) :: :ok
  @impl true
  def close(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Checks if the connection is healthy.
  """
  @spec healthy?(pid()) :: boolean()
  def healthy?(pid) do
    GenServer.call(pid, :healthy?)
  end

  @doc """
  Gets the last used timestamp.
  """
  @spec get_last_used(pid()) :: integer()
  @impl true
  def get_last_used(pid) do
    GenServer.call(pid, :get_last_used)
  end

  @doc """
  Updates the last used timestamp.
  """
  @spec update_last_used(pid()) :: :ok
  @impl true
  def update_last_used(pid) do
    GenServer.call(pid, :update_last_used)
  end

  # GenServer callbacks

  @impl GenServer
  def init({provider, opts}) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    state = %__MODULE__{
      provider: provider,
      client: nil,
      connection_state: :connecting,
      last_used: DateTime.utc_now(),
      retry_count: 0,
      max_retries: max_retries,
      subscription_handles: %{}
    }

    # Attempt initial connection
    case establish_connection(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:query, query_string, variables, opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        case execute_graphql_operation(new_state, :query, query_string, variables, opts) do
          {:ok, result} ->
            {:reply, {:ok, result}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:mutation, mutation_string, variables, opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        case execute_graphql_operation(new_state, :mutation, mutation_string, variables, opts) do
          {:ok, result} ->
            {:reply, {:ok, result}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:subscription, subscription_string, variables, opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        case execute_graphql_subscription(new_state, subscription_string, variables, opts) do
          {:ok, results} ->
            {:reply, {:ok, results}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:introspect_schema, opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        case introspect_graphql_schema(new_state, opts) do
          {:ok, schema} ->
            {:reply, {:ok, schema}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:healthy?, _from, state) do
    healthy = state.connection_state == :connected and state.client != nil
    {:reply, healthy, state}
  end

  def handle_call(:get_last_used, _from, state) do
    {:reply, state.last_used_at, state}
  end

  def handle_call(:update_last_used, _from, state) do
    new_state = %{state | last_used_at: System.monotonic_time(:millisecond)}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    case establish_connection(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Close any active subscriptions
    Enum.each(state.subscription_handles, fn {_key, pid} ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
  end

  # Private functions

  defp establish_connection(state) do
    url = state.provider.url
    headers = build_headers(state.provider)

    client =
      Req.new(
        base_url: url,
        headers: headers,
        json: true,
        retry: false
      )

    # Test the connection with a simple introspection query
    test_query = """
    query IntrospectionQuery {
      __schema {
        queryType {
          name
        }
      }
    }
    """

    case Req.post(client, json: %{query: test_query}) do
      {:ok, %{status: 200, body: _body}} ->
        new_state = %{state | client: client, connection_state: :connected, retry_count: 0}
        Logger.info("GraphQL connection established to #{url}")
        {:ok, new_state}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to connect to GraphQL endpoint #{url}: HTTP #{status} - #{inspect(body)}")

        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Failed to connect to GraphQL endpoint #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during GraphQL connection: #{inspect(error)}")
      {:error, error}
  end

  defp ensure_connected(state) do
    case state.connection_state do
      :connected ->
        {:ok, state}

      _ ->
        case establish_connection(state) do
          {:ok, new_state} -> {:ok, new_state}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp execute_graphql_operation(state, operation_type, operation_string, variables, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    payload = %{
      query: operation_string,
      variables: variables,
      operationName: nil
    }

    case Req.post(state.client, json: payload, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"data" => data, "errors" => nil}}} ->
        {:ok, data}

      {:ok, %{status: 200, body: %{"data" => data, "errors" => errors}}} ->
        Logger.warning("GraphQL #{operation_type} returned errors: #{inspect(errors)}")
        {:ok, data}

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        Logger.error("GraphQL #{operation_type} failed: #{inspect(errors)}")
        {:error, "GraphQL errors: #{inspect(errors)}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("GraphQL #{operation_type} failed with HTTP #{status}: #{inspect(body)}")
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("GraphQL #{operation_type} request failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during GraphQL #{operation_type}: #{inspect(error)}")
      {:error, error}
  end

  defp execute_graphql_subscription(state, subscription_string, variables, opts) do
    # For now, simulate subscription with a single response
    # In a real implementation, this would use WebSocket or Server-Sent Events
    timeout = Keyword.get(opts, :timeout, 30_000)

    payload = %{
      query: subscription_string,
      variables: variables,
      operationName: nil
    }

    case Req.post(state.client, json: payload, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"data" => data, "errors" => nil}}} ->
        # Simulate streaming by wrapping the data
        results = [data]
        {:ok, results}

      {:ok, %{status: 200, body: %{"data" => data, "errors" => errors}}} ->
        Logger.warning("GraphQL subscription returned errors: #{inspect(errors)}")
        results = [data]
        {:ok, results}

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        Logger.error("GraphQL subscription failed: #{inspect(errors)}")
        {:error, "GraphQL errors: #{inspect(errors)}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("GraphQL subscription failed with HTTP #{status}: #{inspect(body)}")
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("GraphQL subscription request failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during GraphQL subscription: #{inspect(error)}")
      {:error, error}
  end

  defp introspect_graphql_schema(state, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    introspection_query = """
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          ...FullType
        }
        directives {
          name
          description
          locations
          args {
            ...InputValue
          }
        }
      }
    }

    fragment FullType on __Type {
      kind
      name
      description
      fields(includeDeprecated: true) {
        name
        description
        args {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }

    fragment InputValue on __InputValue {
      name
      description
      type { ...TypeRef }
      defaultValue
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    payload = %{
      query: introspection_query,
      variables: %{},
      operationName: "IntrospectionQuery"
    }

    case Req.post(state.client, json: payload, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"data" => data, "errors" => nil}}} ->
        {:ok, data}

      {:ok, %{status: 200, body: %{"data" => data, "errors" => errors}}} ->
        Logger.warning("GraphQL introspection returned errors: #{inspect(errors)}")
        {:ok, data}

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        Logger.error("GraphQL introspection failed: #{inspect(errors)}")
        {:error, "GraphQL errors: #{inspect(errors)}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("GraphQL introspection failed with HTTP #{status}: #{inspect(body)}")
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("GraphQL introspection request failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during GraphQL introspection: #{inspect(error)}")
      {:error, error}
  end

  defp build_headers(provider) do
    base_headers = %{
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "User-Agent" => "ExUtcp/0.2.2"
    }

    # Add custom headers
    custom_headers = Map.get(provider, :headers, %{})
    headers = Map.merge(base_headers, custom_headers)

    # Add authentication if configured
    case Map.get(provider, :auth) do
      nil -> headers
      auth -> add_auth_headers(headers, auth)
    end
  end

  defp add_auth_headers(headers, auth) do
    case auth.type do
      :api_key ->
        case auth.location do
          "header" ->
            Map.put(headers, "Authorization", "Bearer #{auth.api_key}")

          "query" ->
            # For query parameters, we'd need to modify the URL
            headers
        end

      :basic ->
        credentials = Base.encode64("#{auth.username}:#{auth.password}")
        Map.put(headers, "Authorization", "Basic #{credentials}")

      :oauth2 ->
        Map.put(headers, "Authorization", "Bearer #{auth.access_token}")

      _ ->
        headers
    end
  end
end
