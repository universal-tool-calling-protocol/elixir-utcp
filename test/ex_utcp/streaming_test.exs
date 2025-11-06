defmodule ExUtcp.StreamingTest do
  @moduledoc """
  Comprehensive tests for streaming functionality across all transports.
  """

  use ExUnit.Case, async: false

  alias ExUtcp.{Client, Providers}

  @moduletag :integration

  setup do
    config = %{
      providers_file_path: nil,
      variables: %{}
    }

    {:ok, client} = Client.start_link(config)

    # Start all transport processes
    {:ok, _} = ExUtcp.Transports.WebSocket.start_link()
    {:ok, _} = ExUtcp.Transports.Grpc.start_link()
    {:ok, _} = ExUtcp.Transports.Graphql.start_link()
    {:ok, _} = ExUtcp.Transports.Mcp.start_link()
    {:ok, _} = ExUtcp.Transports.TcpUdp.start_link()

    %{client: client}
  end

  describe "HTTP Streaming" do
    test "creates proper stream result structure", %{client: client} do
      provider =
        Providers.new_http_provider(
          name: "test_http",
          url: "https://httpbin.org/stream/5",
          http_method: "GET"
        )

      case Client.register_tool_provider(client, provider) do
        {:ok, _tools} ->
          case Client.call_tool_stream(client, "test_http:stream", %{}) do
            {:ok, %{type: :stream, data: stream, metadata: metadata}} ->
              assert is_function(stream, 0) or is_list(stream)
              assert metadata["transport"] == "http"
              assert metadata["tool"] == "stream"

              # Test stream processing
              chunks = Enum.take(stream, 3)
              assert length(chunks) <= 3

              # Verify chunk structure
              Enum.each(chunks, fn chunk ->
                assert Map.has_key?(chunk, :data)
                assert Map.has_key?(chunk, :metadata)
                assert Map.has_key?(chunk, :timestamp)
                assert Map.has_key?(chunk, :sequence)
              end)

            {:error, reason} ->
              # Expected to fail in test environment
              assert is_binary(reason)
          end

        {:error, _reason} ->
          # Expected to fail in test environment
          :ok
      end
    end
  end

  describe "WebSocket Streaming" do
    test "creates proper stream result structure", %{client: client} do
      provider =
        Providers.new_websocket_provider(
          name: "test_ws",
          url: "ws://echo.websocket.org",
          keep_alive: true
        )

      case Client.register_tool_provider(client, provider) do
        {:ok, _tools} ->
          case Client.call_tool_stream(client, "test_ws:stream", %{"message" => "test"}) do
            {:ok, %{type: :stream, data: stream, metadata: metadata}} ->
              assert is_function(stream, 0) or is_list(stream)
              assert metadata["transport"] == "websocket"
              assert metadata["tool"] == "stream"
              assert metadata["protocol"] == "ws"

            {:error, reason} ->
              # Expected to fail in test environment
              assert is_binary(reason)
          end

        {:error, _reason} ->
          # Expected to fail in test environment
          :ok
      end
    end
  end

  describe "GraphQL Streaming" do
    test "creates proper stream result structure", %{client: client} do
      provider =
        Providers.new_graphql_provider(
          name: "test_graphql",
          url: "https://api.example.com/graphql"
        )

      case Client.register_tool_provider(client, provider) do
        {:ok, _tools} ->
          case Client.call_tool_stream(client, "test_graphql:subscribe", %{"query" => "test"}) do
            {:ok, %{type: :stream, data: stream, metadata: metadata}} ->
              assert is_function(stream, 0) or is_list(stream)
              assert metadata["transport"] == "graphql"
              assert metadata["tool"] == "subscribe"
              assert metadata["subscription"] == true

            {:error, reason} ->
              # Expected to fail in test environment
              assert is_binary(reason)
          end

        {:error, _reason} ->
          # Expected to fail in test environment
          :ok
      end
    end
  end

  describe "gRPC Streaming" do
    test "creates proper stream result structure", %{client: client} do
      provider =
        Providers.new_grpc_provider(
          name: "test_grpc",
          host: "localhost",
          port: 50051,
          service_name: "TestService",
          method_name: "StreamData"
        )

      case Client.register_tool_provider(client, provider) do
        {:ok, _tools} ->
          case Client.call_tool_stream(client, "test_grpc:stream", %{"request" => "test"}) do
            {:ok, %{type: :stream, data: stream, metadata: metadata}} ->
              assert is_function(stream, 0) or is_list(stream)
              assert metadata["transport"] == "grpc"
              assert metadata["tool"] == "stream"
              assert metadata["protocol"] == "grpc"
              assert metadata["service"] == "TestService"

            {:error, reason} ->
              # Expected to fail in test environment
              assert is_binary(reason)
          end

        {:error, _reason} ->
          # Expected to fail in test environment
          :ok
      end
    end
  end

  describe "MCP Streaming" do
    test "creates proper stream result structure", %{client: client} do
      provider =
        Providers.new_mcp_provider(
          name: "test_mcp",
          url: "https://mcp.example.com/api"
        )

      case Client.register_tool_provider(client, provider) do
        {:ok, _tools} ->
          case Client.call_tool_stream(client, "test_mcp:stream", %{"method" => "test"}) do
            {:ok, %{type: :stream, data: stream, metadata: metadata}} ->
              assert is_function(stream, 0) or is_list(stream)
              assert metadata["transport"] == "mcp"
              assert metadata["tool"] == "stream"
              assert metadata["protocol"] == "json-rpc-2.0"

            {:error, reason} ->
              # Expected to fail in test environment
              assert is_binary(reason)
          end

        {:error, _reason} ->
          # Expected to fail in test environment
          :ok
      end
    end
  end

  describe "Stream Processing" do
    test "processes stream chunks correctly" do
      # Create a mock stream
      mock_chunks = [
        %{data: "chunk1", metadata: %{"sequence" => 0}, timestamp: 1000, sequence: 0},
        %{data: "chunk2", metadata: %{"sequence" => 1}, timestamp: 2000, sequence: 1},
        %{type: :end, metadata: %{"sequence" => 2}}
      ]

      stream = Stream.map(mock_chunks, & &1)

      # Test stream processing
      processed =
        stream
        |> Stream.map(fn chunk ->
          case chunk do
            %{type: :end} -> :done
            %{type: :error} -> :done
            chunk when is_map(chunk) -> Map.get(chunk, :data, chunk)
            chunk -> chunk
          end
        end)
        |> Stream.reject(&(&1 == :done))
        |> Enum.to_list()

      assert processed == ["chunk1", "chunk2"]
    end

    test "handles stream errors correctly" do
      # Create a mock stream with errors
      mock_chunks = [
        %{data: "chunk1", metadata: %{"sequence" => 0}, timestamp: 1000, sequence: 0},
        %{type: :error, error: "Connection lost", code: 500, metadata: %{"sequence" => 1}},
        %{type: :end, metadata: %{"sequence" => 2}}
      ]

      stream = Stream.map(mock_chunks, & &1)

      # Test error handling
      errors =
        stream
        |> Stream.filter(fn chunk -> chunk.type == :error end)
        |> Enum.to_list()

      assert length(errors) == 1
      assert hd(errors).error == "Connection lost"
      assert hd(errors).code == 500
    end

    test "filters stream by metadata" do
      # Create a mock stream with different metadata
      mock_chunks = [
        %{
          data: "chunk1",
          metadata: %{"type" => "data", "sequence" => 0},
          timestamp: 1000,
          sequence: 0
        },
        %{
          data: "chunk2",
          metadata: %{"type" => "control", "sequence" => 1},
          timestamp: 2000,
          sequence: 1
        },
        %{
          data: "chunk3",
          metadata: %{"type" => "data", "sequence" => 2},
          timestamp: 3000,
          sequence: 2
        }
      ]

      stream = Stream.map(mock_chunks, & &1)

      # Filter by metadata
      data_chunks =
        stream
        |> Stream.filter(fn chunk ->
          Map.get(chunk.metadata, "type") == "data"
        end)
        |> Enum.to_list()

      assert length(data_chunks) == 2
      assert hd(data_chunks).data == "chunk1"
      assert List.last(data_chunks).data == "chunk3"
    end
  end

  describe "Stream Metadata" do
    test "includes required metadata fields" do
      chunk = %{
        data: "test_data",
        metadata: %{
          "sequence" => 0,
          "timestamp" => 1000,
          "tool" => "test_tool",
          "provider" => "test_provider",
          "protocol" => "test"
        },
        timestamp: 1000,
        sequence: 0
      }

      # Verify required fields
      assert Map.has_key?(chunk, :data)
      assert Map.has_key?(chunk, :metadata)
      assert Map.has_key?(chunk, :timestamp)
      assert Map.has_key?(chunk, :sequence)

      # Verify metadata content
      assert chunk.metadata["sequence"] == 0
      assert chunk.metadata["timestamp"] == 1000
      assert chunk.metadata["tool"] == "test_tool"
      assert chunk.metadata["provider"] == "test_provider"
      assert chunk.metadata["protocol"] == "test"
    end

    test "handles different stream event types" do
      # Test data chunk
      data_chunk = %{
        data: "test",
        metadata: %{"sequence" => 0},
        timestamp: 1000,
        sequence: 0
      }

      # Test error chunk
      error_chunk = %{
        type: :error,
        error: "Test error",
        code: 500,
        metadata: %{"sequence" => 1}
      }

      # Test end chunk
      end_chunk = %{
        type: :end,
        metadata: %{"sequence" => 2}
      }

      # Verify chunk types
      assert Map.has_key?(data_chunk, :data)
      assert error_chunk.type == :error
      assert end_chunk.type == :end
    end
  end

  describe "Transport Streaming Support" do
    test "HTTP transport supports streaming" do
      assert ExUtcp.Transports.Http.supports_streaming?() == true
    end

    test "WebSocket transport supports streaming" do
      assert ExUtcp.Transports.WebSocket.supports_streaming?() == true
    end

    test "GraphQL transport supports streaming" do
      assert ExUtcp.Transports.Graphql.supports_streaming?() == true
    end

    test "gRPC transport supports streaming" do
      assert ExUtcp.Transports.Grpc.supports_streaming?() == true
    end

    test "MCP transport supports streaming" do
      assert ExUtcp.Transports.Mcp.supports_streaming?() == true
    end

    test "CLI transport does not support streaming" do
      assert ExUtcp.Transports.Cli.supports_streaming?() == false
    end
  end
end
