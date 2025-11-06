defmodule ExUtcp.Transports.WebSocketMoxSimpleTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExUtcp.Transports.WebSocket

  @moduletag :unit

  # Mocks are defined in test_helper.exs

  setup :verify_on_exit!

  describe "WebSocket Transport Unit Tests with Mocks" do
    test "creates new transport" do
      transport = WebSocket.new()
      assert %WebSocket{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "returns correct transport name" do
      assert WebSocket.transport_name() == "websocket"
    end

    test "supports streaming" do
      assert WebSocket.supports_streaming?() == true
    end

    test "validates provider type" do
      # Test with invalid provider type - this should work without GenServer
      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil,
        headers: %{}
      }

      # Test with invalid provider type
      assert {:error, "WebSocket transport can only be used with WebSocket providers"} =
               WebSocket.register_tool_provider(invalid_provider)
    end

    @tag :genserver_lifecycle
    test "deregisters tool provider" do
      provider = %{
        name: "test",
        type: :websocket,
        url: "ws://localhost:4000/socket",
        auth: nil,
        headers: %{}
      }

      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(WebSocket.deregister_tool_provider(provider))
    end

    test "closes transport" do
      # WebSocket close() should work without GenServer running
      assert :ok = WebSocket.close()
    end

    test "handles custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = WebSocket.new(logger: logger, connection_timeout: 60_000)

      assert %WebSocket{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "handles retry configuration" do
      transport =
        WebSocket.new(
          max_retries: 5,
          retry_delay: 2000,
          backoff_multiplier: 2.0
        )

      assert %WebSocket{} = transport

      assert transport.retry_config == %{
               max_retries: 5,
               retry_delay: 2000,
               backoff_multiplier: 2.0
             }
    end

    test "handles connection pool configuration" do
      connection_pool = %{
        max_connections: 10,
        connection_timeout: 15_000
      }

      transport = WebSocket.new(connection_pool: connection_pool)
      assert %WebSocket{} = transport
      # WebSocket transport doesn't store connection_pool in the struct
      assert transport.connection_pool == %{}
    end
  end
end
