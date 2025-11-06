defmodule ExUtcp.Transports.Mcp.Connection do
  @moduledoc """
  Manages MCP connections with JSON-RPC 2.0 communication.
  """

  @behaviour ExUtcp.Transports.Mcp.ConnectionBehaviour

  use GenServer

  alias ExUtcp.Auth
  alias ExUtcp.Transports.Mcp.Message

  require Logger

  defstruct [
    :provider,
    :client,
    :connection_state,
    :last_used_at,
    :retry_count,
    :max_retries,
    :retry_delay,
    :backoff_multiplier,
    :request_id
  ]

  @doc """
  Starts a new MCP connection.
  """
  @spec start_link(ExUtcp.Types.mcp_provider(), keyword()) :: GenServer.on_start()
  @impl true
  def start_link(provider, opts \\ []) do
    GenServer.start_link(__MODULE__, {provider, opts})
  end

  @doc """
  Calls a tool using JSON-RPC.
  """
  @spec call_tool(pid(), String.t(), map(), keyword()) :: ExUtcp.Types.call_result()
  @impl true
  def call_tool(pid, tool_name, args, opts \\ []) do
    GenServer.call(pid, {:call_tool, tool_name, args, opts})
  end

  @doc """
  Calls a tool with streaming support.
  """
  @spec call_tool_stream(pid(), String.t(), map(), keyword()) :: ExUtcp.Types.call_result()
  @impl true
  def call_tool_stream(pid, tool_name, args, opts \\ []) do
    GenServer.call(pid, {:call_tool_stream, tool_name, args, opts})
  end

  @doc """
  Sends a JSON-RPC request.
  """
  @spec send_request(pid(), String.t(), map(), keyword()) :: ExUtcp.Types.call_result()
  @impl true
  def send_request(pid, method, params, opts \\ []) do
    GenServer.call(pid, {:send_request, method, params, opts})
  end

  @doc """
  Sends a JSON-RPC notification.
  """
  @spec send_notification(pid(), String.t(), map(), keyword()) :: :ok | {:error, String.t()}
  @impl true
  def send_notification(pid, method, params, opts \\ []) do
    GenServer.call(pid, {:send_notification, method, params, opts})
  end

  @doc """
  Closes the connection.
  """
  @spec close(pid()) :: :ok
  @impl true
  def close(pid) do
    GenServer.call(pid, :close)
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
    state = %__MODULE__{
      provider: provider,
      client: nil,
      connection_state: :disconnected,
      last_used_at: System.monotonic_time(:millisecond),
      retry_count: 0,
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 1000),
      backoff_multiplier: Keyword.get(opts, :backoff_multiplier, 2),
      request_id: 1
    }

    case establish_connection(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:call_tool, tool_name, args, opts}, _from, state) do
    case ensure_connection(state) do
      {:ok, new_state} ->
        result = execute_tool_call(tool_name, args, new_state, opts)
        {:reply, result, update_last_used_impl(new_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:call_tool_stream, tool_name, args, opts}, _from, state) do
    case ensure_connection(state) do
      {:ok, new_state} ->
        result = execute_tool_stream(tool_name, args, new_state, opts)
        {:reply, result, update_last_used_impl(new_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_request, method, params, opts}, _from, state) do
    case ensure_connection(state) do
      {:ok, new_state} ->
        result = execute_request(method, params, new_state, opts)
        {:reply, result, update_last_used_impl(new_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_notification, method, params, opts}, _from, state) do
    case ensure_connection(state) do
      {:ok, new_state} ->
        result = execute_notification(method, params, new_state, opts)
        {:reply, result, update_last_used_impl(new_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    {:reply, :ok, %{state | connection_state: :closed}}
  end

  @impl GenServer
  def handle_call(:get_last_used, _from, state) do
    {:reply, state.last_used_at, state}
  end

  @impl GenServer
  def handle_call(:update_last_used, _from, state) do
    new_state = update_last_used(state)
    {:reply, :ok, new_state}
  end

  # Private functions

  defp establish_connection(state) do
    client = build_http_client(state.provider)

    # Test connection with a ping request
    ping_request = Message.build_request("ping", %{})

    case send_http_request(client, ping_request) do
      {:ok, %{status: 200, body: _body}} ->
        new_state = %{state | client: client, connection_state: :connected, retry_count: 0}
        Logger.info("MCP connection established to #{state.provider.url}")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error(
          "Failed to connect to MCP endpoint #{state.provider.url}: #{inspect(reason)}"
        )

        {:error, reason}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Failed to connect to MCP endpoint #{state.provider.url} with HTTP #{status}: #{inspect(body)}"
        )

        {:error, "HTTP #{status}: #{inspect(body)}"}
    end
  rescue
    error ->
      Logger.error("Exception during MCP connection: #{inspect(error)}")
      {:error, error}
  end

  defp ensure_connection(state) do
    case state.connection_state do
      :connected -> {:ok, state}
      _ -> establish_connection(state)
    end
  end

  defp execute_tool_call(tool_name, args, state, _opts) do
    request =
      Message.build_request("tools/call", %{
        name: tool_name,
        arguments: args
      })

    case send_http_request(state.client, request) do
      {:ok, %{status: 200, body: body}} ->
        case Message.parse_response(body) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, "Failed to parse response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}
    end
  end

  defp execute_tool_stream(tool_name, args, state, opts) do
    # For streaming, we'll use Server-Sent Events if available
    # For now, we'll simulate streaming by returning a stream of chunks
    case execute_tool_call(tool_name, args, state, opts) do
      {:ok, result} ->
        # Simulate streaming by chunking the result
        stream =
          Stream.map([result], fn data ->
            case data do
              %{"content" => content} when is_list(content) ->
                Enum.map(content, &%{"chunk" => &1})

              _ ->
                [%{"chunk" => data}]
            end
          end)

        {:ok, stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_request(method, params, state, _opts) do
    request = Message.build_request(method, params)

    case send_http_request(state.client, request) do
      {:ok, %{status: 200, body: body}} ->
        case Message.parse_response(body) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, "Failed to parse response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}
    end
  end

  defp execute_notification(method, params, state, _opts) do
    notification = Message.build_notification(method, params)

    case send_http_request(state.client, notification) do
      {:ok, %{status: 200}} -> :ok
      {:error, reason} -> {:error, "HTTP request failed: #{inspect(reason)}"}
      {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{inspect(body)}"}
    end
  end

  defp send_http_request(client, message) do
    Req.post(client, json: message)
  end

  defp build_http_client(provider) do
    base_url = provider.url
    headers = build_headers(provider)

    Req.new(
      base_url: base_url,
      headers: headers,
      receive_timeout: 30_000,
      retry: false
    )
  end

  defp build_headers(provider) do
    headers = %{
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    case provider.auth do
      nil -> headers
      auth -> add_auth_headers(headers, auth)
    end
  end

  defp add_auth_headers(headers, auth) do
    Auth.apply_to_headers(auth, headers)
  end

  defp update_last_used_impl(state) do
    %{state | last_used_at: System.monotonic_time(:millisecond)}
  end
end
