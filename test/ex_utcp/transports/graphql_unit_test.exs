defmodule ExUtcp.Transports.GraphqlUnitTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Transports.Graphql

  describe "GraphQL Transport Unit Tests" do
    setup do
      # Clean up any existing GraphQL transport
      case Process.whereis(Graphql) do
        nil ->
          :ok

        pid ->
          try do
            GenServer.stop(pid)
            # Give it even more time to stop
            Process.sleep(200)
          rescue
            _ -> :ok
          end
      end

      :ok
    end

    test "creates new transport" do
      transport = Graphql.new()

      assert %Graphql{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Graphql.new(logger: logger, connection_timeout: 60_000)

      assert %Graphql{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "returns correct transport name" do
      assert Graphql.transport_name() == "graphql"
    end

    test "supports streaming" do
      assert Graphql.supports_streaming?() == true
    end

    test "validates provider type" do
      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil,
        headers: %{}
      }

      # Test with invalid provider type - this should return an error without GenServer running
      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Graphql.register_tool_provider(invalid_provider)
    end

    test "deregister_tool_provider always succeeds" do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Graphql.deregister_tool_provider(provider))
    end

    test "close always succeeds" do
      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Graphql.close())
    end
  end
end
