defmodule ExUtcp.Client do
  @moduledoc """
  Main UTCP client implementation.

  This module provides the primary interface for interacting with UTCP providers
  and tools. It manages provider registration, tool discovery, and tool execution.
  """

  use GenServer

  alias ExUtcp.Config
  alias ExUtcp.Monitoring.Performance
  alias ExUtcp.OpenApiConverter
  alias ExUtcp.Providers
  alias ExUtcp.Repository
  alias ExUtcp.Search.Engine, as: SearchEngine
  alias ExUtcp.Tools
  alias ExUtcp.Types, as: T

  defstruct [
    :config,
    :repository,
    :transports,
    :search_strategy
  ]

  @doc """
  Starts a new UTCP client with the given configuration.
  """
  @spec start_link(T.client_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Starts a new UTCP client with the given configuration and name.
  """
  @spec start_link(T.client_config(), GenServer.name()) :: GenServer.on_start()
  def start_link(config, name) do
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @doc """
  Registers a tool provider and returns the discovered tools.
  """
  @spec register_tool_provider(GenServer.server(), T.provider()) :: T.register_result()
  def register_tool_provider(client, provider) do
    GenServer.call(client, {:register_provider, provider})
  end

  @doc """
  Deregisters a tool provider.
  """
  @spec deregister_tool_provider(GenServer.server(), String.t()) :: T.deregister_result()
  def deregister_tool_provider(client, provider_name) do
    GenServer.call(client, {:deregister_provider, provider_name})
  end

  @doc """
  Calls a specific tool with the given arguments.
  """
  @spec call_tool(GenServer.server(), String.t(), map()) :: T.call_result()
  def call_tool(client, tool_name, args \\ %{}) do
    GenServer.call(client, {:call_tool, tool_name, args})
  end

  @doc """
  Calls a tool with streaming support.
  """
  @spec call_tool_stream(GenServer.server(), String.t(), map()) ::
          {:ok, T.stream_result()} | {:error, any()}
  def call_tool_stream(client, tool_name, args \\ %{}) do
    GenServer.call(client, {:call_tool_stream, tool_name, args})
  end

  @doc """
  Searches for tools using advanced search algorithms.

  ## Parameters

  - `client`: UTCP client
  - `query`: Search query string
  - `opts`: Search options including algorithm, filters, and limits

  ## Options

  - `:algorithm` - Search algorithm (:exact, :fuzzy, :semantic, :combined)
  - `:filters` - Map with provider, transport, and tag filters
  - `:limit` - Maximum number of results (default: 20)
  - `:threshold` - Minimum similarity threshold (default: 0.1)
  - `:security_scan` - Enable security scanning (default: false)
  - `:filter_sensitive` - Filter out tools with sensitive data (default: false)

  ## Returns

  List of search results with tools, scores, and match information.
  """
  @spec search_tools(GenServer.server(), String.t(), map()) :: [map()]
  def search_tools(client, query, opts \\ %{}) do
    GenServer.call(client, {:search_tools, query, opts})
  end

  @doc """
  Gets all available transports.
  """
  @spec get_transports(GenServer.server()) :: %{String.t() => module()}
  def get_transports(client) do
    GenServer.call(client, :get_transports)
  end

  @doc """
  Gets the client configuration.
  """
  @spec get_config(GenServer.server()) :: T.client_config()
  def get_config(client) do
    GenServer.call(client, :get_config)
  end

  @doc """
  Gets repository statistics.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(client) do
    GenServer.call(client, :get_stats)
  end

  # GenServer callbacks

  @impl GenServer
  def init(config) do
    repository = Repository.new()
    transports = default_transports()
    search_strategy = default_search_strategy()

    # Load providers from file if specified
    state = %__MODULE__{
      config: config,
      repository: repository,
      transports: transports,
      search_strategy: search_strategy
    }

    if config.providers_file_path do
      case load_providers_from_file(state, config.providers_file_path) do
        {:ok, updated_state} -> {:ok, updated_state}
        {:error, reason} -> {:stop, reason}
      end
    else
      {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:register_provider, provider}, _from, state) do
    case register_provider(state, provider) do
      {:ok, tools, updated_state} -> {:reply, {:ok, tools}, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:deregister_provider, provider_name}, _from, state) do
    case deregister_provider(state, provider_name) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args}, _from, state) do
    # Measure tool call performance
    result =
      Performance.measure_tool_call(tool_name, "unknown", args, fn ->
        call_tool_impl(state, tool_name, args)
      end)

    case result do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args}, _from, state) do
    case call_tool_stream_impl(state, tool_name, args) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:search_tools, query, opts}, _from, state) do
    # Measure search performance
    algorithm = Map.get(opts, :algorithm, :combined)
    filters = Map.get(opts, :filters, %{})

    results =
      Performance.measure_search(query, algorithm, filters, fn ->
        # Create search engine from current repository state
        search_engine = create_search_engine_from_state(state)
        ExUtcp.Search.search_tools(search_engine, query, opts)
      end)

    {:reply, results, state}
  end

  @impl GenServer
  def handle_call(:get_transports, _from, state) do
    {:reply, state.transports, state}
  end

  @impl GenServer
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = %{
      tool_count: Repository.tool_count(state.repository),
      provider_count: Repository.provider_count(state.repository)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:get_monitoring_metrics, _from, state) do
    metrics = ExUtcp.Monitoring.get_metrics()
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:get_health_status, _from, state) do
    health_status = ExUtcp.Monitoring.get_health_status()
    {:reply, health_status, state}
  end

  @impl GenServer
  def handle_call(:get_performance_summary, _from, state) do
    performance_summary = Performance.get_performance_summary()
    {:reply, performance_summary, state}
  end

  @impl GenServer
  def handle_call({:convert_openapi, spec, opts}, _from, state) do
    case convert_openapi_impl(spec, opts) do
      {:ok, tools} ->
        # Register all tools
        {results, new_repo} =
          Enum.reduce(tools, {[], state.repository}, fn tool, {acc_results, repo} ->
            case Repository.add_tool(repo, tool) do
              {:ok, new_repo} -> {[{:ok, tool} | acc_results], new_repo}
              {:error, reason} -> {[{:error, reason} | acc_results], repo}
            end
          end)

        # Check if any registration failed
        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:reply, {:ok, tools}, %{state | repository: new_repo}}
          error -> {:reply, error, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:convert_multiple_openapi, specs, opts}, _from, state) do
    case convert_multiple_openapi_impl(specs, opts) do
      {:ok, tools} ->
        # Register all tools
        {results, new_repo} =
          Enum.reduce(tools, {[], state.repository}, fn tool, {acc_results, repo} ->
            case Repository.add_tool(repo, tool) do
              {:ok, new_repo} -> {[{:ok, tool} | acc_results], new_repo}
              {:error, reason} -> {[{:error, reason} | acc_results], repo}
            end
          end)

        # Check if any registration failed
        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:reply, {:ok, tools}, %{state | repository: new_repo}}
          error -> {:reply, error, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:validate_openapi, spec}, _from, state) do
    result = OpenApiConverter.validate(spec)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:search_providers, query, opts}, _from, state) do
    # Create search engine from current repository state
    search_engine = create_search_engine_from_state(state)

    results = ExUtcp.Search.search_providers(search_engine, query, opts)
    {:reply, results, state}
  end

  @impl GenServer
  def handle_call({:get_search_suggestions, partial_query, opts}, _from, state) do
    # Create search engine from current repository state
    search_engine = create_search_engine_from_state(state)

    suggestions = ExUtcp.Search.get_suggestions(search_engine, partial_query, opts)
    {:reply, suggestions, state}
  end

  @impl GenServer
  def handle_call({:find_similar_tools, tool_name, opts}, _from, state) do
    case Repository.get_tool(state.repository, tool_name) do
      {:ok, tool} ->
        # Create search engine from current repository state
        search_engine = create_search_engine_from_state(state)

        similar_tools = ExUtcp.Search.suggest_similar_tools(search_engine, tool, opts)
        {:reply, similar_tools, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private functions

  defp default_transports do
    %{
      "http" => ExUtcp.Transports.Http,
      "cli" => ExUtcp.Transports.Cli,
      "websocket" => ExUtcp.Transports.WebSocket,
      "grpc" => ExUtcp.Transports.Grpc,
      "graphql" => ExUtcp.Transports.Graphql,
      "mcp" => ExUtcp.Transports.Mcp,
      "webrtc" => ExUtcp.Transports.WebRTC
      # Add more transports as they are implemented
    }
  end

  defp default_search_strategy do
    # Simple search strategy - can be enhanced later
    fn repository, query, limit ->
      Repository.search_tools(repository, query, limit)
    end
  end

  defp load_providers_from_file(state, file_path) do
    # Validate file path to prevent directory traversal
    with {:ok, validated_path} <- validate_file_path(file_path),
         {:ok, content} <- File.read(validated_path),
         {:ok, data} <- Jason.decode(content) do
      parse_and_register_providers(state, data)
    else
      {:error, :invalid_path} -> {:error, "Invalid file path"}
      {:error, %Jason.DecodeError{} = reason} -> {:error, "Failed to parse JSON: #{inspect(reason)}"}
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp validate_file_path(file_path) do
    # Resolve to absolute path and check for directory traversal
    abs_path = Path.expand(file_path)

    # Check if path contains directory traversal patterns
    cond do
      String.contains?(file_path, ["../", "..\\"]) ->
        {:error, :invalid_path}

      # Ensure the path doesn't escape the current working directory
      String.contains?(abs_path, "..") ->
        {:error, :invalid_path}

      # Check if file exists and is readable
      not File.exists?(abs_path) ->
        {:error, :file_not_found}

      true ->
        {:ok, abs_path}
    end
  end

  defp parse_and_register_providers(state, data) do
    providers_data =
      case data do
        %{"providers" => providers} when is_list(providers) -> providers
        %{"providers" => provider} when is_map(provider) -> [provider]
        providers when is_list(providers) -> providers
        provider when is_map(provider) -> [provider]
        _ -> []
      end

    updated_state =
      Enum.reduce(providers_data, state, fn provider_data, acc_state ->
        case parse_provider(provider_data) do
          {:ok, provider} ->
            case register_provider(acc_state, provider) do
              {:ok, _tools, new_state} -> new_state
              {:error, _reason} -> acc_state
            end

          {:error, _reason} ->
            acc_state
        end
      end)

    {:ok, updated_state}
  end

  defp parse_provider(provider_data) do
    provider_type = Map.get(provider_data, "type") || Map.get(provider_data, "provider_type")

    case provider_type do
      "http" -> parse_http_provider(provider_data)
      "cli" -> parse_cli_provider(provider_data)
      "websocket" -> parse_websocket_provider(provider_data)
      "grpc" -> parse_grpc_provider(provider_data)
      "graphql" -> parse_graphql_provider(provider_data)
      "mcp" -> parse_mcp_provider(provider_data)
      _ -> {:error, "Unknown provider type: #{provider_type}"}
    end
  end

  defp parse_http_provider(data) do
    provider =
      Providers.new_http_provider(
        name: Map.get(data, "name", ""),
        http_method: Map.get(data, "http_method", "GET"),
        url: Map.get(data, "url", ""),
        content_type: Map.get(data, "content_type", "application/json"),
        auth: parse_auth(Map.get(data, "auth")),
        headers: Map.get(data, "headers", %{}),
        body_field: Map.get(data, "body_field"),
        header_fields: Map.get(data, "header_fields", [])
      )

    {:ok, provider}
  end

  defp parse_cli_provider(data) do
    provider =
      Providers.new_cli_provider(
        name: Map.get(data, "name", ""),
        command_name: Map.get(data, "command_name", ""),
        working_dir: Map.get(data, "working_dir"),
        env_vars: Map.get(data, "env_vars", %{})
      )

    {:ok, provider}
  end

  defp parse_websocket_provider(data) do
    provider =
      Providers.new_websocket_provider(
        name: Map.get(data, "name", ""),
        url: Map.get(data, "url", ""),
        protocol: Map.get(data, "protocol"),
        keep_alive: Map.get(data, "keep_alive", false),
        auth: parse_auth(Map.get(data, "auth")),
        headers: Map.get(data, "headers", %{}),
        header_fields: Map.get(data, "header_fields", [])
      )

    {:ok, provider}
  end

  defp parse_grpc_provider(data) do
    provider =
      Providers.new_grpc_provider(
        name: Map.get(data, "name", ""),
        host: Map.get(data, "host", "127.0.0.1"),
        port: Map.get(data, "port", 9339),
        service_name: Map.get(data, "service_name", "UTCPService"),
        method_name: Map.get(data, "method_name", "CallTool"),
        target: Map.get(data, "target"),
        use_ssl: Map.get(data, "use_ssl", false),
        auth: parse_auth(Map.get(data, "auth"))
      )

    {:ok, provider}
  end

  defp parse_graphql_provider(data) do
    provider =
      Providers.new_graphql_provider(
        name: Map.get(data, "name", ""),
        url: Map.get(data, "url", ""),
        auth: parse_auth(Map.get(data, "auth")),
        headers: Map.get(data, "headers", %{})
      )

    {:ok, provider}
  end

  defp parse_mcp_provider(data) do
    provider =
      Providers.new_mcp_provider(
        name: Map.get(data, "name", ""),
        url: Map.get(data, "url", ""),
        auth: parse_auth(Map.get(data, "auth"))
      )

    {:ok, provider}
  end

  defp parse_auth(nil), do: nil

  defp parse_auth(auth_data) do
    case Map.get(auth_data, "type") || Map.get(auth_data, "auth_type") do
      "api_key" -> ExUtcp.Auth.new_api_key_auth(auth_data)
      "basic" -> ExUtcp.Auth.new_basic_auth(auth_data)
      "oauth2" -> ExUtcp.Auth.new_oauth2_auth(auth_data)
      _ -> nil
    end
  end

  defp register_provider(state, provider) do
    # Apply variable substitution
    substituted_provider = Config.substitute_variables(state.config, provider)

    # Normalize provider name
    normalized_name = Providers.normalize_name(Providers.get_name(substituted_provider))
    substituted_provider = Providers.set_name(substituted_provider, normalized_name)

    # Get transport
    transport_module = Map.get(state.transports, to_string(substituted_provider.type))

    if is_nil(transport_module) do
      {:error, "No transport available for provider type: #{substituted_provider.type}"}
    else
      # Register with transport
      case transport_module.register_tool_provider(substituted_provider) do
        {:ok, tools} ->
          # Normalize tool names
          normalized_tools =
            Enum.map(tools, fn tool ->
              normalized_name = Tools.normalize_name(tool.name, normalized_name)
              Map.put(tool, :name, normalized_name)
            end)

          # Save to repository
          updated_repository =
            Repository.save_provider_with_tools(
              state.repository,
              substituted_provider,
              normalized_tools
            )

          updated_state = %{state | repository: updated_repository}
          {:ok, normalized_tools, updated_state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp deregister_provider(state, provider_name) do
    case Repository.get_provider(state.repository, provider_name) do
      nil ->
        {:error, "Provider not found: #{provider_name}"}

      provider ->
        # Get transport
        transport_module = Map.get(state.transports, to_string(provider.type))

        if is_nil(transport_module) do
          {:error, "No transport available for provider type: #{provider.type}"}
        else
          # Deregister with transport
          transport_module.deregister_tool_provider(provider)

          # Remove from repository
          updated_repository = Repository.remove_provider(state.repository, provider_name)
          updated_state = %{state | repository: updated_repository}
          {:ok, updated_state}
        end
    end
  end

  defp call_tool_impl(state, tool_name, args) do
    with {:ok, _tool} <- get_tool_or_error(state.repository, tool_name),
         provider_name = Tools.extract_provider_name(tool_name),
         {:ok, provider} <- get_provider_or_error(state.repository, provider_name),
         {:ok, transport_module} <- get_transport_or_error(state.transports, provider.type) do
      call_name = extract_call_name(provider.type, tool_name)
      _transport = transport_module.new()
      transport_module.call_tool(call_name, args, provider)
    end
  end

  defp get_tool_or_error(repository, tool_name) do
    case Repository.get_tool(repository, tool_name) do
      nil -> {:error, "Tool not found: #{tool_name}"}
      tool -> {:ok, tool}
    end
  end

  defp get_provider_or_error(repository, provider_name) do
    case Repository.get_provider(repository, provider_name) do
      nil -> {:error, "Provider not found: #{provider_name}"}
      provider -> {:ok, provider}
    end
  end

  defp get_transport_or_error(transports, provider_type) do
    case Map.get(transports, to_string(provider_type)) do
      nil -> {:error, "No transport available for provider type: #{provider_type}"}
      transport_module -> {:ok, transport_module}
    end
  end

  defp extract_call_name(provider_type, tool_name) do
    if provider_type in [:mcp, :text] do
      Tools.extract_tool_name(tool_name)
    else
      tool_name
    end
  end

  defp call_tool_stream_impl(state, tool_name, args) do
    with {:ok, _tool} <- get_tool_or_error(state.repository, tool_name),
         provider_name = Tools.extract_provider_name(tool_name),
         {:ok, provider} <- get_provider_or_error(state.repository, provider_name),
         {:ok, transport_module} <- get_transport_or_error(state.transports, provider.type) do
      call_name = extract_call_name(provider.type, tool_name)
      _transport = transport_module.new()
      transport_module.call_tool_stream(call_name, args, provider)
    end
  end

  @doc """
  Converts an OpenAPI specification to UTCP tools and registers them.

  ## Parameters

  - `client`: UTCP client
  - `spec`: OpenAPI specification (map, URL, or file path)
  - `opts`: Conversion options

  ## Returns

  `{:ok, tools}` on success, `{:error, reason}` on failure.
  """
  @spec convert_openapi(GenServer.server(), map() | String.t(), keyword()) :: T.register_result()
  def convert_openapi(client, spec, opts \\ []) do
    GenServer.call(client, {:convert_openapi, spec, opts})
  end

  @doc """
  Converts multiple OpenAPI specifications to UTCP tools and registers them.

  ## Parameters

  - `client`: UTCP client
  - `specs`: List of OpenAPI specifications
  - `opts`: Conversion options

  ## Returns

  `{:ok, tools}` on success, `{:error, reason}` on failure.
  """
  @spec convert_multiple_openapi(GenServer.server(), list(), keyword()) :: T.register_result()
  def convert_multiple_openapi(client, specs, opts \\ []) do
    GenServer.call(client, {:convert_multiple_openapi, specs, opts})
  end

  @doc """
  Validates an OpenAPI specification.

  ## Parameters

  - `client`: UTCP client
  - `spec`: OpenAPI specification

  ## Returns

  `{:ok, validation_result}` on success, `{:error, reason}` on failure.
  """
  @spec validate_openapi(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def validate_openapi(client, spec) do
    GenServer.call(client, {:validate_openapi, spec})
  end

  @doc """
  Searches for providers using advanced search algorithms.

  ## Parameters

  - `client`: UTCP client
  - `query`: Search query string
  - `opts`: Search options

  ## Returns

  List of search results with providers, scores, and match information.
  """
  @spec search_providers(GenServer.server(), String.t(), map()) :: [map()]
  def search_providers(client, query, opts \\ %{}) do
    GenServer.call(client, {:search_providers, query, opts})
  end

  @doc """
  Gets search suggestions based on partial query.

  ## Parameters

  - `client`: UTCP client
  - `partial_query`: Partial search query
  - `opts`: Suggestion options

  ## Returns

  List of suggested search terms.
  """
  @spec get_search_suggestions(GenServer.server(), String.t(), keyword()) :: [String.t()]
  def get_search_suggestions(client, partial_query, opts \\ []) do
    GenServer.call(client, {:get_search_suggestions, partial_query, opts})
  end

  @doc """
  Finds similar tools based on a reference tool.

  ## Parameters

  - `client`: UTCP client
  - `tool_name`: Name of the reference tool
  - `opts`: Similarity search options

  ## Returns

  List of similar tools with similarity scores.
  """
  @spec find_similar_tools(GenServer.server(), String.t(), keyword()) :: [map()]
  def find_similar_tools(client, tool_name, opts \\ []) do
    GenServer.call(client, {:find_similar_tools, tool_name, opts})
  end

  @doc """
  Gets monitoring metrics for the client.

  ## Parameters

  - `client`: UTCP client

  ## Returns

  Map containing current metrics and performance data.
  """
  @spec get_monitoring_metrics(GenServer.server()) :: map()
  def get_monitoring_metrics(client) do
    GenServer.call(client, :get_monitoring_metrics)
  end

  @doc """
  Gets health status for the client and its components.

  ## Parameters

  - `client`: UTCP client

  ## Returns

  Map containing health status information.
  """
  @spec get_health_status(GenServer.server()) :: map()
  def get_health_status(client) do
    GenServer.call(client, :get_health_status)
  end

  @doc """
  Gets performance summary for client operations.

  ## Parameters

  - `client`: UTCP client

  ## Returns

  Map containing performance statistics and alerts.
  """
  @spec get_performance_summary(GenServer.server()) :: map()
  def get_performance_summary(client) do
    GenServer.call(client, :get_performance_summary)
  end

  # Private functions

  defp create_search_engine_from_state(state) do
    # Create a search engine and populate it with current tools and providers
    search_engine = SearchEngine.new()

    # Add all tools from repository
    tools = Repository.get_tools(state.repository)

    search_engine =
      Enum.reduce(tools, search_engine, fn tool, acc ->
        SearchEngine.add_tool(acc, tool)
      end)

    # Add all providers from repository
    providers = Repository.get_providers(state.repository)

    search_engine =
      Enum.reduce(providers, search_engine, fn provider, acc ->
        SearchEngine.add_provider(acc, provider)
      end)

    search_engine
  end

  defp convert_openapi_impl(spec, opts) when is_map(spec) do
    OpenApiConverter.convert(spec, opts)
  end

  defp convert_openapi_impl(url, opts) when is_binary(url) do
    if String.starts_with?(url, "http") do
      OpenApiConverter.convert_from_url(url, opts)
    else
      OpenApiConverter.convert_from_file(url, opts)
    end
  end

  defp convert_multiple_openapi_impl(specs, opts) do
    OpenApiConverter.convert_multiple(specs, opts)
  end
end
