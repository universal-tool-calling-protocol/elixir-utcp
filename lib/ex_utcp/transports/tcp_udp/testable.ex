defmodule ExUtcp.Transports.TcpUdp.Testable do
  @moduledoc """
  Testable module for TCP/UDP transport to enable mocking in tests.

  This module provides a way to inject mocks for the TCP/UDP transport components
  during testing, allowing for isolated unit tests.
  """

  alias ExUtcp.Transports.TcpUdp.{Connection, Pool}

  @doc """
  Sets the mock modules for testing.
  """
  def set_mocks(connection_behaviour, pool_behaviour) do
    # Store the behaviours in application env for the transport to use
    Application.put_env(:ex_utcp, :tcp_udp_connection_behaviour, connection_behaviour)
    Application.put_env(:ex_utcp, :tcp_udp_pool_behaviour, pool_behaviour)
    :ok
  end

  @doc """
  Gets the mock module for connections.
  """
  def get_connection_mock do
    Application.get_env(:ex_utcp, :tcp_udp_connection_mock, Connection)
  end

  @doc """
  Gets the mock module for pools.
  """
  def get_pool_mock do
    Application.get_env(:ex_utcp, :tcp_udp_pool_mock, Pool)
  end

  @doc """
  Clears all mocks.
  """
  def clear_mocks do
    # Mox doesn't have a clear function, so we just return :ok
    :ok
  end

  @doc """
  Creates a mock connection for testing.
  """
  def create_mock_connection(provider) do
    connection_mock = get_connection_mock()
    connection_mock.start_link(provider)
  end

  @doc """
  Creates a mock pool for testing.
  """
  def create_mock_pool(opts \\ []) do
    pool_mock = get_pool_mock()
    pool_mock.start_link(opts)
  end

  @doc """
  Mocks a tool call response.
  """
  def mock_tool_call_response(tool_name, args, response) do
    # This would be used by the mock modules to return predefined responses
    %{
      tool: tool_name,
      args: args,
      response: response,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Mocks a tool stream response.
  """
  def mock_tool_stream_response(tool_name, args, stream_data) do
    # This would be used by the mock modules to return predefined stream responses
    stream =
      Stream.map(stream_data, fn data ->
        %{
          type: :stream,
          data: data,
          tool: tool_name,
          timestamp: System.monotonic_time(:millisecond)
        }
      end)

    %{
      tool: tool_name,
      args: args,
      stream: stream,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Mocks a connection error.
  """
  def mock_connection_error(reason) do
    {:error, reason}
  end

  @doc """
  Mocks a pool error.
  """
  def mock_pool_error(reason) do
    {:error, reason}
  end

  @doc """
  Validates a TCP provider configuration.
  """
  def validate_tcp_provider(provider) do
    required_fields = [:name, :host, :port, :protocol]

    case Enum.find(required_fields, &(not Map.has_key?(provider, &1))) do
      nil -> :ok
      field -> {:error, "TCP provider missing required field: #{field}"}
    end
  end

  @doc """
  Validates a UDP provider configuration.
  """
  def validate_udp_provider(provider) do
    required_fields = [:name, :host, :port, :protocol]

    case Enum.find(required_fields, &(not Map.has_key?(provider, &1))) do
      nil -> :ok
      field -> {:error, "UDP provider missing required field: #{field}"}
    end
  end

  @doc """
  Creates a test TCP provider.
  """
  def create_test_tcp_provider(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "test_tcp"),
      type: :tcp,
      protocol: :tcp,
      host: Keyword.get(opts, :host, "localhost"),
      port: Keyword.get(opts, :port, 8080),
      timeout: Keyword.get(opts, :timeout, 5000),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a test UDP provider.
  """
  def create_test_udp_provider(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "test_udp"),
      type: :udp,
      protocol: :udp,
      host: Keyword.get(opts, :host, "localhost"),
      port: Keyword.get(opts, :port, 8080),
      timeout: Keyword.get(opts, :timeout, 5000),
      auth: Keyword.get(opts, :auth, nil)
    }
  end

  @doc """
  Creates a test tool.
  """
  def create_test_tool(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "test_tool"),
      description: Keyword.get(opts, :description, "A test tool"),
      inputs: %{
        type: "object",
        properties: %{
          "message" => %{
            type: "string",
            description: "The message to send"
          }
        },
        required: ["message"]
      },
      outputs: %{
        type: "object",
        properties: %{
          "response" => %{
            type: "string",
            description: "The response from the tool"
          }
        },
        required: ["response"]
      },
      tags: Keyword.get(opts, :tags, ["test"]),
      average_response_size: Keyword.get(opts, :average_response_size, 100),
      provider: Keyword.get(opts, :provider, create_test_tcp_provider())
    }
  end
end
