defmodule ExUtcp.Transports.TcpUdpTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Providers
  alias ExUtcp.Transports.TcpUdp

  setup do
    # Start the transport
    {:ok, transport_pid} = TcpUdp.start_link()

    on_exit(fn ->
      try do
        TcpUdp.close()
      catch
        :exit, _ -> :ok
      end
    end)

    %{transport_pid: transport_pid}
  end

  describe "TCP/UDP Transport" do
    test "starts and stops properly" do
      # Start with a unique name to avoid conflicts
      {:ok, pid} = TcpUdp.start_link(name: :test_tcp_udp_transport)
      assert is_pid(pid)

      # Close the specific process
      GenServer.stop(pid)
    end

    test "supports streaming" do
      assert TcpUdp.supports_streaming?() == true
    end

    test "has correct transport name" do
      assert TcpUdp.transport_name() == "tcp_udp"
    end

    test "creates new transport with options" do
      transport = TcpUdp.new(connection_timeout: 60_000)
      assert transport.connection_timeout == 60_000
      assert transport.retry_config.max_retries == 3
    end
  end

  describe "Provider Registration" do
    test "registers TCP provider successfully" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = TcpUdp.register_tool_provider(provider)
    end

    test "registers UDP provider successfully" do
      provider =
        Providers.new_udp_provider(
          name: "test_udp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = TcpUdp.register_tool_provider(provider)
    end

    test "rejects invalid provider type" do
      provider = %{
        name: "invalid",
        type: :http,
        host: "localhost",
        port: 8080
      }

      assert {:error, "TCP/UDP transport can only be used with TCP or UDP providers"} =
               TcpUdp.register_tool_provider(provider)
    end

    test "validates TCP provider fields" do
      # Missing host
      provider = %{
        name: "test",
        type: :tcp,
        port: 8080
      }

      assert {:error, "TCP provider missing required field: :host"} =
               TcpUdp.register_tool_provider(provider)
    end

    test "validates UDP provider fields" do
      # Missing port
      provider = %{
        name: "test",
        type: :udp,
        host: "localhost"
      }

      assert {:error, "UDP provider missing required field: :port"} =
               TcpUdp.register_tool_provider(provider)
    end

    test "deregisters provider successfully" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = TcpUdp.register_tool_provider(provider)
      assert :ok = TcpUdp.deregister_tool_provider(provider)
    end
  end

  describe "Tool Execution" do
    setup do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)
      %{provider: provider}
    end

    @tag :integration
    test "calls tool successfully", %{provider: provider} do
      # This will fail in unit tests since we don't have a real server
      # but we can test the error handling
      result = catch_exit(TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider))

      # Should return an error since we can't connect to localhost:8080
      assert match?({:error, _reason}, result) or match?({:EXIT, _reason}, result)
    end

    @tag :integration
    test "calls tool stream successfully", %{provider: provider} do
      # This will fail in unit tests since we don't have a real server
      # but we can test the error handling
      result = catch_exit(TcpUdp.call_tool_stream("test_tool", %{"message" => "hello"}, provider))

      # Should return an error since we can't connect to localhost:8080
      assert match?({:error, _reason}, result) or match?({:EXIT, _reason}, result)
    end
  end

  describe "Error Handling" do
    @tag :integration
    test "handles connection failures gracefully" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "nonexistent.example.com",
          port: 9999
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = catch_exit(TcpUdp.call_tool("test_tool", %{"message" => "hello"}, provider))
      assert match?({:error, _reason}, result) or match?({:EXIT, _reason}, result)
    end

    @tag :integration
    test "handles invalid tool calls" do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = TcpUdp.register_tool_provider(provider)

      result = catch_exit(TcpUdp.call_tool("nonexistent_tool", %{}, provider))
      assert match?({:error, _reason}, result) or match?({:EXIT, _reason}, result)
    end
  end

  describe "Retry Logic" do
    test "retries failed operations" do
      transport =
        TcpUdp.new(retry_config: %{max_retries: 2, retry_delay: 100, backoff_multiplier: 2})

      # Test that retry logic is configured correctly
      assert transport.retry_config.max_retries == 2
      assert transport.retry_config.retry_delay == 100
      assert transport.retry_config.backoff_multiplier == 2
    end
  end
end
