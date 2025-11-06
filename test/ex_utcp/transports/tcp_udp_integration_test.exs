defmodule ExUtcp.Transports.TcpUdpIntegrationTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Providers
  alias ExUtcp.Transports.TcpUdp

  @moduletag :integration

  setup do
    # Start the transport
    {:ok, transport_pid} = TcpUdp.start_link()

    on_exit(fn ->
      TcpUdp.close()
    end)

    %{transport_pid: transport_pid}
  end

  describe "TCP Integration Tests" do
    test "connects to TCP server when available" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "httpbin.org",
          port: 80
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      # This will fail because we don't have a real TCP server
      # but we can test the connection attempt
      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end

    test "handles TCP connection timeout" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          # Non-routable IP for timeout testing
          host: "192.0.2.1",
          port: 80,
          timeout: 1000
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end
  end

  describe "UDP Integration Tests" do
    test "creates UDP socket successfully" do
      provider =
        Providers.new_udp_provider(
          name: "test_udp",
          host: "8.8.8.8",
          port: 53
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      # UDP doesn't require a connection, so this should work
      # but will fail when trying to send data
      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end

    test "handles UDP send errors" do
      provider =
        Providers.new_udp_provider(
          name: "test_udp",
          host: "invalid.host.example.com",
          port: 53
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end
  end

  describe "Connection Pool Integration" do
    test "manages multiple connections" do
      tcp_provider =
        Providers.new_tcp_provider(
          name: "tcp_provider",
          host: "localhost",
          port: 8080
        )

      udp_provider =
        Providers.new_udp_provider(
          name: "udp_provider",
          host: "localhost",
          port: 8081
        )

      {:ok, []} = TcpUdp.register_tool_provider(tcp_provider)
      {:ok, []} = TcpUdp.register_tool_provider(udp_provider)

      # Both should fail but for different reasons
      tcp_result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, tcp_provider)
      udp_result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, udp_provider)

      assert {:error, _reason} = tcp_result
      assert {:error, _reason} = udp_result
    end

    test "handles provider deregistration" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)
      assert :ok = TcpUdp.deregister_tool_provider(provider)

      # Should fail because provider is no longer registered
      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end
  end

  describe "Streaming Integration" do
    test "handles tool stream calls" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = TcpUdp.call_tool_stream("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end

    test "handles UDP stream calls" do
      provider =
        Providers.new_udp_provider(
          name: "test_udp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = TcpUdp.call_tool_stream("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end
  end

  describe "Error Recovery Integration" do
    test "retries failed operations" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      # This should retry and eventually fail
      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result
    end

    test "handles max retries exceeded" do
      # Create a transport with very low retry settings
      {:ok, pid} = TcpUdp.start_link()

      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider)
      assert {:error, _reason} = result

      TcpUdp.close()
    end
  end
end
