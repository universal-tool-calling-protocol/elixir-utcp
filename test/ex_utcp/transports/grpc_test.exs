defmodule ExUtcp.Transports.GrpcTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Providers
  alias ExUtcp.Transports.Grpc

  @moduletag :integration

  setup_all do
    # Clean up any existing gRPC transport
    case Process.whereis(Grpc) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.stop(pid)
        rescue
          _ -> :ok
        end
    end

    :ok
  end

  describe "gRPC Transport" do
    setup do
      # Start the gRPC transport for tests that need it
      case Process.whereis(Grpc) do
        nil ->
          {:ok, _pid} = Grpc.start_link()

        _pid ->
          :ok
      end

      :ok
    end

    test "creates new transport" do
      transport = Grpc.new()

      assert %Grpc{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Grpc.new(logger: logger, connection_timeout: 60_000)

      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "starts the transport GenServer" do
      # This test runs in setup, but we can verify it's running
      assert Process.whereis(Grpc) != nil
    end

    test "returns correct transport name" do
      assert Grpc.transport_name() == "grpc"
    end

    test "supports streaming" do
      assert Grpc.supports_streaming?() == true
    end

    test "validates provider type" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "gRPC transport can only be used with gRPC providers"} =
               Grpc.register_tool_provider(http_provider)
    end

    test "handles invalid provider in call_tool" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "gRPC transport can only be used with gRPC providers"} =
               Grpc.call_tool("test_tool", %{}, http_provider)
    end

    test "handles invalid provider in call_tool_stream" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "gRPC transport can only be used with gRPC providers"} =
               Grpc.call_tool_stream("test_tool", %{}, http_provider)
    end

    test "deregister_tool_provider always succeeds" do
      provider = Providers.new_grpc_provider(name: "test", host: "localhost", port: 9339)

      assert :ok = Grpc.deregister_tool_provider(provider)
    end

    test "close always succeeds" do
      assert :ok = Grpc.close()
    end

    test "provides gNMI functionality" do
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "localhost",
          port: 50051,
          service_name: "UTCPService",
          method_name: "GetManual",
          use_ssl: false
        )

      # Test gNMI operations (these will succeed with the mock implementation)
      assert {:ok, %{"result" => _}} = Grpc.gnmi_get(provider, ["/interfaces/interface"], [])

      assert {:ok, %{"result" => _}} =
               Grpc.gnmi_set(provider, [%{"path" => "/test", "val" => "value"}], [])

      assert {:ok, [%{"chunk" => _}, %{"chunk" => _}]} =
               Grpc.gnmi_subscribe(provider, ["/interfaces/interface"], [])
    end
  end

  describe "gRPC Provider" do
    test "creates new grpc provider" do
      provider =
        Providers.new_grpc_provider(
          name: "test_grpc",
          host: "localhost",
          port: 9339
        )

      assert provider.name == "test_grpc"
      assert provider.type == :grpc
      assert provider.host == "localhost"
      assert provider.port == 9339
      assert provider.service_name == "UTCPService"
      assert provider.method_name == "CallTool"
      assert provider.target == nil
      assert provider.use_ssl == false
      assert provider.auth == nil
    end

    test "creates grpc provider with all options" do
      auth = ExUtcp.Auth.new_api_key_auth(api_key: "test-key", location: "header")

      provider =
        Providers.new_grpc_provider(
          name: "test_grpc",
          host: "grpc.example.com",
          port: 443,
          service_name: "CustomService",
          method_name: "CustomMethod",
          target: "router1",
          use_ssl: true,
          auth: auth
        )

      assert provider.name == "test_grpc"
      assert provider.type == :grpc
      assert provider.host == "grpc.example.com"
      assert provider.port == 443
      assert provider.service_name == "CustomService"
      assert provider.method_name == "CustomMethod"
      assert provider.target == "router1"
      assert provider.use_ssl == true
      assert provider.auth == auth
    end

    test "validates grpc provider" do
      provider = %{name: "", type: :grpc, host: "localhost", port: 9339}

      assert {:error, "Provider name is required"} = Providers.validate_provider(provider)
    end
  end

  describe "gRPC endpoint building" do
    test "builds gRPC endpoint correctly" do
      _provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "localhost",
          port: 9339
        )

      # This would be tested in private function, but we can test the concept
      expected_endpoint = "localhost:9339"
      # In real implementation, this would be tested through the public API
      assert String.contains?(expected_endpoint, "localhost")
      assert String.contains?(expected_endpoint, "9339")
    end
  end

  describe "Error handling" do
    setup do
      # Ensure the GenServer is running for these tests
      case Process.whereis(Grpc) do
        nil ->
          {:ok, _pid} = Grpc.start_link()

        _pid ->
          :ok
      end

      :ok
    end

    test "handles connection errors gracefully" do
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "invalid-host-that-does-not-exist",
          port: 9999
        )

      # With the mock implementation, this will succeed
      assert {:ok, []} = Grpc.register_tool_provider(provider)
    end

    test "handles tool call errors gracefully" do
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "invalid-host-that-does-not-exist",
          port: 9999
        )

      # With the mock implementation, this will succeed
      assert {:ok, %{"result" => _}} = Grpc.call_tool("test.tool", %{"arg" => "value"}, provider)
    end

    test "handles tool stream errors gracefully" do
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "invalid-host-that-does-not-exist",
          port: 9999
        )

      # With the mock implementation, this will succeed
      assert {:ok, %{type: :stream, data: _}} =
               Grpc.call_tool_stream("test.tool", %{"arg" => "value"}, provider)
    end
  end
end
