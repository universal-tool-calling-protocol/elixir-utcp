defmodule ExUtcp.Providers do
  @moduledoc """
  Provider implementations for different protocols.

  This module contains the data structures and functions for various provider types
  including HTTP, CLI, WebSocket, gRPC, GraphQL, TCP, UDP, WebRTC, MCP, and Text providers.
  """

  alias ExUtcp.Types, as: T

  @doc """
  Creates a new HTTP provider.
  """
  @spec new_http_provider(keyword()) :: T.http_provider()
  def new_http_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :http,
      http_method: Keyword.get(opts, :http_method, "GET"),
      url: Keyword.fetch!(opts, :url),
      content_type: Keyword.get(opts, :content_type, "application/json"),
      auth: Keyword.get(opts, :auth, nil),
      headers: Keyword.get(opts, :headers, %{}),
      body_field: Keyword.get(opts, :body_field, nil),
      header_fields: Keyword.get(opts, :header_fields, [])
    }
  end

  @doc """
  Creates a new CLI provider.
  """
  @spec new_cli_provider(keyword()) :: T.cli_provider()
  def new_cli_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :cli,
      command_name: Keyword.fetch!(opts, :command_name),
      working_dir: Keyword.get(opts, :working_dir, nil),
      env_vars: Keyword.get(opts, :env_vars, %{})
    }
  end

  @doc """
  Creates a new WebSocket provider.
  """
  @spec new_websocket_provider(keyword()) :: T.websocket_provider()
  def new_websocket_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :websocket,
      url: Keyword.fetch!(opts, :url),
      protocol: Keyword.get(opts, :protocol, nil),
      keep_alive: Keyword.get(opts, :keep_alive, false),
      auth: Keyword.get(opts, :auth, nil),
      headers: Keyword.get(opts, :headers, %{}),
      header_fields: Keyword.get(opts, :header_fields, [])
    }
  end

  @doc """
  Creates a new gRPC provider.
  """
  @spec new_grpc_provider(keyword()) :: T.grpc_provider()
  def new_grpc_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :grpc,
      host: Keyword.get(opts, :host, "127.0.0.1"),
      port: Keyword.get(opts, :port, 9339),
      service_name: Keyword.get(opts, :service_name, "UTCPService"),
      method_name: Keyword.get(opts, :method_name, "CallTool"),
      target: Keyword.get(opts, :target, nil),
      use_ssl: Keyword.get(opts, :use_ssl, false),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a new GraphQL provider.
  """
  @spec new_graphql_provider(keyword()) :: T.graphql_provider()
  def new_graphql_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :graphql,
      url: Keyword.fetch!(opts, :url),
      auth: Keyword.get(opts, :auth, nil),
      headers: Keyword.get(opts, :headers, %{})
    }
  end

  @doc """
  Creates a new WebRTC provider.
  """
  @spec new_webrtc_provider(keyword()) :: T.webrtc_provider()
  def new_webrtc_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :webrtc,
      peer_id: Keyword.get(opts, :peer_id),
      signaling_server: Keyword.get(opts, :signaling_server, "wss://signaling.example.com"),
      ice_servers:
        Keyword.get(opts, :ice_servers, [
          %{urls: ["stun:stun.l.google.com:19302"]}
        ]),
      timeout: Keyword.get(opts, :timeout, 30_000),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  @doc """
  Creates a new MCP provider.
  """
  @spec new_mcp_provider(keyword()) :: T.mcp_provider()
  def new_mcp_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :mcp,
      url: Keyword.fetch!(opts, :url),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a new TCP provider.
  """
  @spec new_tcp_provider(keyword()) :: T.tcp_provider()
  def new_tcp_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :tcp,
      protocol: :tcp,
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port),
      timeout: Keyword.get(opts, :timeout, 5000),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a new UDP provider.
  """
  @spec new_udp_provider(keyword()) :: T.udp_provider()
  def new_udp_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :udp,
      protocol: :udp,
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port),
      timeout: Keyword.get(opts, :timeout, 5000),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a new Text provider.
  """
  @spec new_text_provider(keyword()) :: T.text_provider()
  def new_text_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :text,
      file_path: Keyword.fetch!(opts, :file_path)
    }
  end

  @doc """
  Creates a new SSE provider.
  """
  @spec new_sse_provider(keyword()) :: T.sse_provider()
  def new_sse_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :sse,
      url: Keyword.fetch!(opts, :url),
      auth: Keyword.get(opts, :auth, nil),
      headers: Keyword.get(opts, :headers, %{})
    }
  end

  @doc """
  Creates a new Streamable HTTP provider.
  """
  @spec new_streamable_http_provider(keyword()) :: T.streamable_http_provider()
  def new_streamable_http_provider(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      type: :http_stream,
      url: Keyword.fetch!(opts, :url),
      auth: Keyword.get(opts, :auth, nil),
      headers: Keyword.get(opts, :headers, %{})
    }
  end

  @doc """
  Gets the provider name from a provider struct.
  """
  @spec get_name(T.provider()) :: String.t()
  def get_name(provider) do
    Map.get(provider, :name, "")
  end

  @doc """
  Gets the provider type from a provider struct.
  """
  @spec get_type(T.provider()) :: T.provider_type()
  def get_type(provider) do
    Map.get(provider, :type, :http)
  end

  @doc """
  Sets the provider name.
  """
  @spec set_name(T.provider(), String.t()) :: T.provider()
  def set_name(provider, name) do
    Map.put(provider, :name, name)
  end

  @doc """
  Validates a provider configuration.
  """
  @spec validate_provider(T.provider()) :: :ok | {:error, String.t()}
  def validate_provider(provider) do
    cond do
      is_nil(Map.get(provider, :name)) or Map.get(provider, :name) == "" ->
        {:error, "Provider name is required"}

      is_nil(Map.get(provider, :type)) ->
        {:error, "Provider type is required"}

      true ->
        :ok
    end
  end

  @doc """
  Normalizes provider name by replacing dots with underscores.
  """
  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) do
    String.replace(name, ".", "_")
  end
end
