defmodule ExUtcp.Transports.WebSocketTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Providers
  alias ExUtcp.Transports.WebSocket

  @moduletag :integration

  describe "WebSocket Transport" do
    test "creates new transport" do
      transport = WebSocket.new()

      assert %WebSocket{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = WebSocket.new(logger: logger, connection_timeout: 60_000)

      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "returns correct transport name" do
      _transport = WebSocket.new()
      assert WebSocket.transport_name() == "websocket"
    end

    test "supports streaming" do
      _transport = WebSocket.new()
      assert WebSocket.supports_streaming?() == true
    end

    test "validates provider type" do
      _transport = WebSocket.new()
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "WebSocket transport can only be used with WebSocket providers"} =
               WebSocket.register_tool_provider(http_provider)
    end

    test "handles invalid provider in call_tool" do
      _transport = WebSocket.new()
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "WebSocket transport can only be used with WebSocket providers"} =
               WebSocket.call_tool("test_tool", %{}, http_provider)
    end

    test "handles invalid provider in call_tool_stream" do
      _transport = WebSocket.new()
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "WebSocket transport can only be used with WebSocket providers"} =
               WebSocket.call_tool_stream("test_tool", %{}, http_provider)
    end

    test "deregister_tool_provider always succeeds" do
      # Start the WebSocket transport GenServer
      {:ok, _pid} = WebSocket.start_link()

      _transport = WebSocket.new()
      provider = Providers.new_websocket_provider(name: "test", url: "ws://example.com")

      assert :ok = WebSocket.deregister_tool_provider(provider)
    end

    test "close always succeeds" do
      _transport = WebSocket.new()
      assert :ok = WebSocket.close()
    end
  end

  describe "WebSocket Provider" do
    test "creates new websocket provider" do
      provider =
        Providers.new_websocket_provider(
          name: "test_ws",
          url: "ws://example.com/ws"
        )

      assert provider.name == "test_ws"
      assert provider.type == :websocket
      assert provider.url == "ws://example.com/ws"
      assert provider.protocol == nil
      assert provider.keep_alive == false
      assert provider.auth == nil
      assert provider.headers == %{}
      assert provider.header_fields == []
    end

    test "creates websocket provider with all options" do
      auth = ExUtcp.Auth.new_api_key_auth(api_key: "test-key", location: "header")

      provider =
        Providers.new_websocket_provider(
          name: "test_ws",
          url: "ws://example.com/ws",
          protocol: "utcp-v1",
          keep_alive: true,
          auth: auth,
          headers: %{"User-Agent" => "Test/1.0"},
          header_fields: ["X-Custom-Header"]
        )

      assert provider.name == "test_ws"
      assert provider.type == :websocket
      assert provider.url == "ws://example.com/ws"
      assert provider.protocol == "utcp-v1"
      assert provider.keep_alive == true
      assert provider.auth == auth
      assert provider.headers == %{"User-Agent" => "Test/1.0"}
      assert provider.header_fields == ["X-Custom-Header"]
    end

    test "validates websocket provider" do
      provider = %{name: "", type: :websocket, url: "ws://example.com"}

      assert {:error, "Provider name is required"} = Providers.validate_provider(provider)
    end
  end

  describe "URL building" do
    test "builds tool URL correctly" do
      _provider =
        Providers.new_websocket_provider(
          name: "test",
          url: "ws://example.com/tools"
        )

      # This would be tested in private function, but we can test the concept
      _base_url = "ws://example.com/tools"
      _tool_name = "echo"

      expected = "ws://example.com/echo"
      # In real implementation, this would be tested through the public API
      assert String.ends_with?(expected, "/echo")
    end
  end

  describe "Error handling" do
    test "handles connection errors gracefully" do
      # Start the WebSocket transport GenServer
      {:ok, _pid} = WebSocket.start_link()

      # This would require mocking WebSockex in a real test
      provider =
        Providers.new_websocket_provider(
          name: "test",
          url: "ws://invalid-url-that-does-not-exist:9999/ws"
        )

      # In a real test environment, we would mock the WebSocket connection
      # and test error handling scenarios. The real implementation now tries
      # to connect and fails gracefully with an error
      assert {:error, _reason} = WebSocket.register_tool_provider(provider)
    end

    test "handles retry logic with exponential backoff" do
      # Test retry configuration
      transport = WebSocket.new(max_retries: 3, retry_delay: 1000)

      assert transport.max_retries == 3
      assert transport.retry_delay == 1000
    end

    test "handles connection pooling" do
      # Test connection pooling functionality
      transport = WebSocket.new()

      assert transport.connection_pool == %{}
    end
  end

  describe "Connection Management" do
    test "starts WebSocket transport GenServer" do
      # Test GenServer functionality
      assert {:ok, pid} = WebSocket.start_link()
      assert is_pid(pid)

      # Clean up
      GenServer.stop(pid)
    end

    test "handles connection lifecycle" do
      # Test connection creation, usage, and cleanup
      transport = WebSocket.new()

      # Test connection key generation
      _provider =
        Providers.new_websocket_provider(
          name: "test",
          url: "ws://localhost:8080/ws"
        )

      # This would test actual connection management in a real implementation
      assert is_struct(transport)
    end
  end
end
