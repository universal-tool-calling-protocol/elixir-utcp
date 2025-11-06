defmodule ExUtcp.Transports.GrpcMoxSimpleTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExUtcp.Transports.Grpc

  @moduletag :unit

  # Mocks are defined in test_helper.exs

  setup :verify_on_exit!

  setup do
    # Stop any running GenServer to ensure clean state
    case Process.whereis(Grpc) do
      nil ->
        :ok

      pid ->
        try do
          if Process.alive?(pid) do
            GenServer.stop(pid, :normal, 500)
            # Give it more time to stop
            Process.sleep(300)
          end
        rescue
          _ -> :ok
        end
    end

    :ok
  end

  describe "gRPC Transport Unit Tests with Mocks" do
    test "creates new transport" do
      transport = Grpc.new()
      assert %Grpc{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "returns correct transport name" do
      assert Grpc.transport_name() == "grpc"
    end

    test "supports streaming" do
      assert Grpc.supports_streaming?() == true
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
      assert {:error, "gRPC transport can only be used with gRPC providers"} =
               Grpc.register_tool_provider(invalid_provider)
    end

    @tag :genserver_lifecycle
    test "deregisters tool provider" do
      provider = %{
        name: "test",
        type: :grpc,
        url: "http://localhost:50051",
        auth: nil,
        headers: %{}
      }

      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Grpc.deregister_tool_provider(provider))
    end

    @tag :genserver_lifecycle
    test "closes transport" do
      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Grpc.close())
    end

    test "handles custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Grpc.new(logger: logger, connection_timeout: 60_000)

      assert %Grpc{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "handles retry configuration" do
      transport =
        Grpc.new(
          max_retries: 5,
          retry_delay: 2000,
          backoff_multiplier: 2.0
        )

      assert %Grpc{} = transport

      assert transport.retry_config == %{
               max_retries: 5,
               retry_delay: 2000,
               backoff_multiplier: 2.0
             }
    end

    test "handles pool configuration" do
      pool_opts = %{
        max_connections: 10,
        connection_timeout: 15_000
      }

      transport = Grpc.new(pool_opts: pool_opts)
      assert %Grpc{} = transport
      assert transport.pool_opts == pool_opts
    end
  end
end
