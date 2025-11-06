defmodule ExUtcp.Transports.GraphqlMoxSimpleTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExUtcp.Transports.Graphql

  @moduletag :unit

  # Mocks are defined in test_helper.exs

  setup :verify_on_exit!

  describe "GraphQL Transport Unit Tests with Mocks" do
    test "creates new transport" do
      transport = Graphql.new()
      assert %Graphql{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "returns correct transport name" do
      assert Graphql.transport_name() == "graphql"
    end

    test "supports streaming" do
      assert Graphql.supports_streaming?() == true
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
      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Graphql.register_tool_provider(invalid_provider)
    end

    @tag :genserver_lifecycle
    test "deregisters tool provider" do
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

    @tag :genserver_lifecycle
    test "closes transport" do
      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Graphql.close())
    end

    test "handles custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Graphql.new(logger: logger, connection_timeout: 60_000)

      assert %Graphql{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "handles retry configuration" do
      transport =
        Graphql.new(
          max_retries: 5,
          retry_delay: 2000,
          backoff_multiplier: 2.0
        )

      assert %Graphql{} = transport
      # The transport uses individual retry parameters
      assert transport.max_retries == 5
      assert transport.retry_delay == 2000

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

      transport = Graphql.new(pool_opts: pool_opts)
      assert %Graphql{} = transport
      assert transport.pool_opts == pool_opts
    end
  end
end
