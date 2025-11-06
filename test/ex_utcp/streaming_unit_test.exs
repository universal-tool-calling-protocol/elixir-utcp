defmodule ExUtcp.StreamingUnitTest do
  @moduledoc """
  Unit tests for streaming functionality that don't require running GenServers.
  """

  use ExUnit.Case, async: true

  @moduletag :unit

  describe "Stream Types and Structures" do
    test "stream_chunk type structure" do
      chunk = %{
        data: "test_data",
        metadata: %{"sequence" => 0, "timestamp" => 1000},
        timestamp: 1000,
        sequence: 0
      }

      # Verify required fields
      assert Map.has_key?(chunk, :data)
      assert Map.has_key?(chunk, :metadata)
      assert Map.has_key?(chunk, :timestamp)
      assert Map.has_key?(chunk, :sequence)

      # Verify data types
      assert is_binary(chunk.data)
      assert is_map(chunk.metadata)
      assert is_integer(chunk.timestamp)
      assert is_integer(chunk.sequence)
    end

    test "stream_result type structure" do
      stream = Stream.map([1, 2, 3], &%{data: &1, sequence: &1})

      result = %{
        type: :stream,
        data: stream,
        metadata: %{"transport" => "test", "tool" => "test_tool"}
      }

      # Verify required fields
      assert result.type == :stream
      # Stream is a struct
      assert %Stream{} = result.data
      assert is_map(result.metadata)
    end

    test "stream_error type structure" do
      error = %{
        type: :error,
        error: "Connection failed",
        code: 500,
        metadata: %{"sequence" => 1}
      }

      # Verify required fields
      assert error.type == :error
      assert is_binary(error.error)
      assert is_integer(error.code)
      assert is_map(error.metadata)
    end

    test "stream_end type structure" do
      end_event = %{
        type: :end,
        metadata: %{"sequence" => 2}
      }

      # Verify required fields
      assert end_event.type == :end
      assert is_map(end_event.metadata)
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
            chunk -> chunk.data
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
        |> Stream.filter(fn chunk -> Map.get(chunk, :type) == :error end)
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

    test "aggregates stream statistics" do
      # Create a mock stream with mixed content
      mock_chunks = [
        %{data: "chunk1", metadata: %{"sequence" => 0}, timestamp: 1000, sequence: 0},
        %{type: :error, error: "Error 1", code: 500, metadata: %{"sequence" => 1}},
        %{data: "chunk2", metadata: %{"sequence" => 2}, timestamp: 2000, sequence: 2},
        %{type: :error, error: "Error 2", code: 404, metadata: %{"sequence" => 3}},
        %{type: :end, metadata: %{"sequence" => 4}}
      ]

      stream = Stream.map(mock_chunks, & &1)

      # Aggregate statistics
      {data_chunks, error_count, total_count} =
        stream
        |> Enum.reduce({[], 0, 0}, fn chunk, {acc, errors, count} ->
          case chunk do
            %{type: :error} ->
              {acc, errors + 1, count + 1}

            %{type: :end} ->
              {acc, errors, count + 1}

            chunk ->
              {[chunk | acc], errors, count + 1}
          end
        end)

      assert length(data_chunks) == 2
      assert error_count == 2
      assert total_count == 5
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

  describe "Stream Creation Helpers" do
    test "creates HTTP stream with proper metadata" do
      # Simulate HTTP streaming
      data = ["chunk1", "chunk2", "chunk3"]
      tool_name = "test_tool"
      provider_name = "test_provider"

      stream =
        data
        |> Stream.with_index(0)
        |> Stream.map(fn {chunk, index} ->
          %{
            data: chunk,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider_name,
              "transport" => "http"
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
        end)

      result = %{
        type: :stream,
        data: stream,
        metadata: %{"transport" => "http", "tool" => tool_name}
      }

      assert result.type == :stream
      assert %Stream{} = result.data
      assert result.metadata["transport"] == "http"
      assert result.metadata["tool"] == tool_name
    end

    test "creates WebSocket stream with proper metadata" do
      # Simulate WebSocket streaming
      data = [%{"message" => "hello"}, %{"message" => "world"}]
      tool_name = "chat_tool"
      provider_name = "websocket_provider"

      stream =
        data
        |> Stream.with_index(0)
        |> Stream.map(fn {chunk, index} ->
          %{
            data: chunk,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider_name,
              "protocol" => "ws"
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
        end)

      result = %{
        type: :stream,
        data: stream,
        metadata: %{"transport" => "websocket", "tool" => tool_name, "protocol" => "ws"}
      }

      assert result.type == :stream
      assert %Stream{} = result.data
      assert result.metadata["transport"] == "websocket"
      assert result.metadata["protocol"] == "ws"
    end

    test "creates GraphQL stream with subscription metadata" do
      # Simulate GraphQL subscription streaming
      data = [%{"data" => %{"update" => "value1"}}, %{"data" => %{"update" => "value2"}}]
      tool_name = "subscribe_updates"
      provider_name = "graphql_provider"

      stream =
        data
        |> Stream.with_index(0)
        |> Stream.map(fn {chunk, index} ->
          %{
            data: chunk,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider_name,
              "subscription" => true
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
        end)

      result = %{
        type: :stream,
        data: stream,
        metadata: %{"transport" => "graphql", "tool" => tool_name, "subscription" => true}
      }

      assert result.type == :stream
      assert %Stream{} = result.data
      assert result.metadata["transport"] == "graphql"
      assert result.metadata["subscription"] == true
    end

    test "creates gRPC stream with service metadata" do
      # Simulate gRPC streaming
      data = [%{"result" => "response1"}, %{"result" => "response2"}]
      tool_name = "stream_data"
      provider_name = "grpc_provider"
      service_name = "StreamingService"

      stream =
        data
        |> Stream.with_index(0)
        |> Stream.map(fn {chunk, index} ->
          %{
            data: chunk,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider_name,
              "protocol" => "grpc",
              "service" => service_name
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
        end)

      result = %{
        type: :stream,
        data: stream,
        metadata: %{
          "transport" => "grpc",
          "tool" => tool_name,
          "protocol" => "grpc",
          "service" => service_name
        }
      }

      assert result.type == :stream
      assert %Stream{} = result.data
      assert result.metadata["transport"] == "grpc"
      assert result.metadata["service"] == service_name
    end

    test "creates MCP stream with JSON-RPC metadata" do
      # Simulate MCP streaming
      data = [
        %{"method" => "tools/call", "result" => "success1"},
        %{"method" => "tools/call", "result" => "success2"}
      ]

      tool_name = "mcp_tool"
      provider_name = "mcp_provider"

      stream =
        data
        |> Stream.with_index(0)
        |> Stream.map(fn {chunk, index} ->
          %{
            data: chunk,
            metadata: %{
              "sequence" => index,
              "timestamp" => System.monotonic_time(:millisecond),
              "tool" => tool_name,
              "provider" => provider_name,
              "protocol" => "json-rpc-2.0"
            },
            timestamp: System.monotonic_time(:millisecond),
            sequence: index
          }
        end)

      result = %{
        type: :stream,
        data: stream,
        metadata: %{"transport" => "mcp", "tool" => tool_name, "protocol" => "json-rpc-2.0"}
      }

      assert result.type == :stream
      assert %Stream{} = result.data
      assert result.metadata["transport"] == "mcp"
      assert result.metadata["protocol"] == "json-rpc-2.0"
    end
  end

  describe "Stream Error Handling" do
    test "handles different error types" do
      errors = [
        %{type: :error, error: "Connection timeout", code: 408, metadata: %{"sequence" => 1}},
        %{type: :error, error: "Server error", code: 500, metadata: %{"sequence" => 2}},
        %{type: :error, error: "Authentication failed", code: 401, metadata: %{"sequence" => 3}}
      ]

      # Test error categorization
      timeout_errors = Enum.filter(errors, &(&1.code == 408))
      server_errors = Enum.filter(errors, &(&1.code >= 500))
      auth_errors = Enum.filter(errors, &(&1.code == 401))

      assert length(timeout_errors) == 1
      assert length(server_errors) == 1
      assert length(auth_errors) == 1

      assert hd(timeout_errors).error == "Connection timeout"
      assert hd(server_errors).error == "Server error"
      assert hd(auth_errors).error == "Authentication failed"
    end

    test "handles stream termination" do
      chunks = [
        %{data: "chunk1", metadata: %{"sequence" => 0}, timestamp: 1000, sequence: 0},
        %{data: "chunk2", metadata: %{"sequence" => 1}, timestamp: 2000, sequence: 1},
        %{type: :end, metadata: %{"sequence" => 2}}
      ]

      stream = Stream.map(chunks, & &1)

      # Test stream termination detection
      {data_chunks, end_detected} =
        stream
        |> Enum.reduce({[], false}, fn chunk, {acc, ended} ->
          case chunk do
            %{type: :end} -> {acc, true}
            chunk -> {[chunk | acc], ended}
          end
        end)

      assert end_detected == true
      assert length(data_chunks) == 2
    end
  end
end
