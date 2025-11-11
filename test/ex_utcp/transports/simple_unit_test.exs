defmodule ExUtcp.Transports.SimpleUnitTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Transports.Cli
  alias ExUtcp.Transports.Graphql
  alias ExUtcp.Transports.Grpc
  alias ExUtcp.Transports.Http
  alias ExUtcp.Transports.WebSocket

  describe "Transport Unit Tests" do
    test "GraphQL transport basic functions" do
      transport = Graphql.new()
      assert %Graphql{} = transport
      assert Graphql.transport_name() == "graphql"
      assert Graphql.supports_streaming?() == true
    end

    test "gRPC transport basic functions" do
      transport = Grpc.new()
      assert %Grpc{} = transport
      assert Grpc.transport_name() == "grpc"
      assert Grpc.supports_streaming?() == true
    end

    test "WebSocket transport basic functions" do
      transport = WebSocket.new()
      assert %WebSocket{} = transport
      assert WebSocket.transport_name() == "websocket"
      assert WebSocket.supports_streaming?() == true
    end

    test "HTTP transport basic functions" do
      transport = Http.new()
      assert %Http{} = transport
      assert Http.transport_name() == "http"
      assert Http.supports_streaming?() == true
    end

    test "CLI transport basic functions" do
      transport = Cli.new()
      assert %Cli{} = transport
      assert Cli.transport_name() == "cli"
      assert Cli.supports_streaming?() == false
    end

    test "GraphQL transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Graphql.new(logger: logger, connection_timeout: 60_000)

      assert %Graphql{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "gRPC transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Grpc.new(logger: logger, connection_timeout: 60_000)

      assert %Grpc{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "WebSocket transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = WebSocket.new(logger: logger, connection_timeout: 60_000)

      assert %WebSocket{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end
  end
end
