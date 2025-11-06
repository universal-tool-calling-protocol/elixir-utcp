defmodule ExUtcp.Transports.GrpcUnitTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Transports.Grpc

  describe "gRPC Transport Unit Tests" do
    setup do
      # Clean up any existing gRPC transport
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

    test "creates new transport" do
      transport = Grpc.new()

      assert %Grpc{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Grpc.new(logger: logger, connection_timeout: 60_000)

      assert %Grpc{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "returns correct transport name" do
      assert Grpc.transport_name() == "grpc"
    end

    test "supports streaming" do
      assert Grpc.supports_streaming?() == true
    end

    test "validates provider type" do
      # Start the transport for this test
      {:ok, _pid} = Grpc.start_link()

      valid_provider = %{
        name: "test",
        type: :grpc,
        url: "http://localhost:50051",
        auth: nil,
        headers: %{}
      }

      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil,
        headers: %{}
      }

      # Test with valid provider
      assert {:ok, []} = Grpc.register_tool_provider(valid_provider)

      # Test with invalid provider type
      assert {:error, "gRPC transport can only be used with gRPC providers"} =
               Grpc.register_tool_provider(invalid_provider)
    end

    test "deregister_tool_provider always succeeds" do
      # Start the transport for this test
      {:ok, _pid} = Grpc.start_link()

      provider = %{
        name: "test",
        type: :grpc,
        url: "http://localhost:50051",
        auth: nil,
        headers: %{}
      }

      assert :ok = Grpc.deregister_tool_provider(provider)
    end

    test "close always succeeds" do
      # Start the transport for this test
      {:ok, _pid} = Grpc.start_link()

      assert :ok = Grpc.close()
    end
  end
end
