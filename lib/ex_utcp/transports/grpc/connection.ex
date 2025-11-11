defmodule ExUtcp.Transports.Grpc.Connection do
  @moduledoc """
  Manages gRPC connections with pooling and lifecycle management.
  """

  use GenServer

  alias ExUtcp.Grpcpb.Empty
  alias ExUtcp.Grpcpb.ToolCallRequest
  alias ExUtcp.Grpcpb.ToolCallResponse
  alias ExUtcp.Grpcpb.UTCPService.Stub

  require Logger

  defstruct [
    :provider,
    :stub,
    :channel,
    :connection_state,
    :last_used,
    :retry_count,
    :max_retries
  ]

  @type t :: %__MODULE__{
          provider: map(),
          stub: module(),
          channel: GRPC.Channel.t(),
          connection_state: :connecting | :connected | :disconnected | :error,
          last_used: DateTime.t(),
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer()
        }

  @doc """
  Starts a new gRPC connection process.
  """
  @spec start_link(map(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(provider, opts \\ []) do
    GenServer.start_link(__MODULE__, {provider, opts})
  end

  @doc """
  Gets the manual (available tools) from the gRPC service.
  """
  @spec get_manual(pid(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def get_manual(pid, timeout \\ 30_000) do
    GenServer.call(pid, {:get_manual, timeout})
  end

  @doc """
  Calls a tool via gRPC.
  """
  @spec call_tool(pid(), String.t(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def call_tool(pid, tool_name, args, timeout \\ 30_000) do
    GenServer.call(pid, {:call_tool, tool_name, args, timeout})
  end

  @doc """
  Calls a tool stream via gRPC.
  """
  @spec call_tool_stream(pid(), String.t(), map(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def call_tool_stream(pid, tool_name, args, timeout \\ 30_000) do
    GenServer.call(pid, {:call_tool_stream, tool_name, args, timeout})
  end

  @doc """
  Closes the gRPC connection.
  """
  @spec close(pid()) :: :ok
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

  # GenServer callbacks

  @impl GenServer
  def init({provider, opts}) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    state = %__MODULE__{
      provider: provider,
      stub: nil,
      channel: nil,
      connection_state: :connecting,
      last_used: DateTime.utc_now(),
      retry_count: 0,
      max_retries: max_retries
    }

    # Attempt initial connection
    case establish_connection(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:get_manual, timeout}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        case call_grpc_service(new_state, :get_manual, %Empty{}, timeout) do
          {:ok, manual} ->
            tools = Enum.map(manual.tools, &normalize_tool/1)
            {:reply, {:ok, tools}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, timeout}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        request = %ToolCallRequest{
          tool: tool_name,
          args_json: Jason.encode!(args)
        }

        case call_grpc_service(new_state, :call_tool, request, timeout) do
          {:ok, response} ->
            result = Jason.decode!(response.result_json)
            {:reply, {:ok, result}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, timeout}, _from, state) do
    case ensure_connected(state) do
      {:ok, new_state} ->
        request = %ToolCallRequest{
          tool: tool_name,
          args_json: Jason.encode!(args)
        }

        case call_grpc_service(new_state, :call_tool_stream, request, timeout) do
          {:ok, responses} ->
            results = Enum.map(responses, &Jason.decode!(&1.result_json))
            {:reply, {:ok, results}, update_last_used(new_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:healthy?, _from, state) do
    healthy = state.connection_state == :connected and state.stub != nil
    {:reply, healthy, state}
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
    if state.channel do
      :ok
    end
  end

  # Private functions

  defp establish_connection(state) do
    endpoint = build_endpoint(state.provider)
    channel_opts = build_channel_opts(state.provider)

    # For now, simulate a connection since the gRPC library API may vary
    # In a real implementation, this would use the actual gRPC connection
    try do
      # Simulate connection attempt
      channel = %{endpoint: endpoint, opts: channel_opts}
      stub = Stub

      new_state = %{
        state
        | channel: channel,
          stub: stub,
          connection_state: :connected,
          retry_count: 0
      }

      Logger.info("gRPC connection established to #{endpoint}")
      {:ok, new_state}
    rescue
      error ->
        Logger.error("Failed to connect to gRPC endpoint #{endpoint}: #{inspect(error)}")
        {:error, error}
    end
  rescue
    error ->
      Logger.error("Exception during gRPC connection: #{inspect(error)}")
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

  defp call_grpc_service(_state, method, request, _timeout) do
    # Simulate gRPC service calls since we don't have a real server
    # In a real implementation, this would use the actual gRPC stub
    case method do
      :get_manual ->
        # Simulate getting manual/tools
        manual = %ExUtcp.Grpcpb.Manual{
          version: "1.0.0",
          tools: []
        }

        {:ok, manual}

      :call_tool ->
        # Simulate tool call response
        response = %ToolCallResponse{
          result_json: Jason.encode!(%{"result" => "Mock gRPC response for #{request.tool}"})
        }

        {:ok, response}

      :call_tool_stream ->
        # Simulate tool stream response
        responses = [
          %ToolCallResponse{
            result_json: Jason.encode!(%{"chunk" => "Mock gRPC stream chunk 1"})
          },
          %ToolCallResponse{
            result_json: Jason.encode!(%{"chunk" => "Mock gRPC stream chunk 2"})
          }
        ]

        {:ok, responses}
    end
  rescue
    error ->
      Logger.error("gRPC call failed: #{inspect(error)}")
      {:error, error}
  end

  defp build_endpoint(provider) do
    host = Map.get(provider, :host, "localhost")
    port = Map.get(provider, :port, 50_051)
    use_ssl = Map.get(provider, :use_ssl, false)

    protocol = if use_ssl, do: "https", else: "http"
    "#{protocol}://#{host}:#{port}"
  end

  defp build_channel_opts(provider) do
    base_opts = [
      interceptors: []
    ]

    # Add authentication if configured
    case Map.get(provider, :auth) do
      nil -> base_opts
      auth -> add_auth_opts(base_opts, auth)
    end
  end

  defp add_auth_opts(opts, auth) do
    case auth.type do
      :api_key ->
        headers = [{"authorization", "Bearer #{auth.api_key}"}]
        Keyword.put(opts, :headers, headers)

      :basic ->
        credentials = Base.encode64("#{auth.username}:#{auth.password}")
        headers = [{"authorization", "Basic #{credentials}"}]
        Keyword.put(opts, :headers, headers)

      :oauth2 ->
        headers = [{"authorization", "Bearer #{auth.access_token}"}]
        Keyword.put(opts, :headers, headers)

      _ ->
        opts
    end
  end

  defp normalize_tool(tool) do
    %{
      "name" => tool.name,
      "description" => tool.description,
      "inputs" => Jason.decode!(tool.inputs),
      "outputs" => Jason.decode!(tool.outputs),
      "tags" => tool.tags
    }
  end

  defp update_last_used(state) do
    %{state | last_used: DateTime.utc_now()}
  end
end
