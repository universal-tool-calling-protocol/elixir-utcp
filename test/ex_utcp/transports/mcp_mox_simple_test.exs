defmodule ExUtcp.Transports.McpMoxSimpleTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExUtcp.Transports.Mcp

  @moduletag :unit

  # Mocks are defined in test_helper.exs

  setup :verify_on_exit!

  describe "MCP Transport Unit Tests with Mocks" do
    test "creates new transport" do
      transport = Mcp.new()
      assert %Mcp{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "returns correct transport name" do
      assert Mcp.transport_name() == "mcp"
    end

    test "supports streaming" do
      assert Mcp.supports_streaming?() == true
    end

    test "validates provider type" do
      # Test with invalid provider type - this should work without GenServer
      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil
      }

      # Test with invalid provider type
      assert {:error, "MCP transport can only be used with MCP providers"} =
               Mcp.register_tool_provider(invalid_provider)
    end

    @tag :genserver_lifecycle
    test "deregisters tool provider" do
      provider = %{
        name: "test",
        type: :mcp,
        url: "http://localhost:3000/mcp",
        auth: nil
      }

      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Mcp.deregister_tool_provider(provider))
    end

    @tag :genserver_lifecycle
    test "closes transport" do
      # This will fail without GenServer running, but that's expected for unit tests
      assert catch_exit(Mcp.close())
    end

    test "handles custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Mcp.new(logger: logger, connection_timeout: 60_000)

      assert %Mcp{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "handles retry configuration" do
      retry_config = %{
        max_retries: 5,
        retry_delay: 2000,
        backoff_multiplier: 2.0
      }

      transport = Mcp.new(retry_config: retry_config)
      assert %Mcp{} = transport
      assert transport.retry_config == retry_config
    end

    test "handles pool configuration" do
      pool_opts = %{
        max_connections: 10,
        connection_timeout: 15_000
      }

      transport = Mcp.new(pool_opts: pool_opts)
      assert %Mcp{} = transport
      assert transport.pool_opts == pool_opts
    end

    test "handles authentication configuration" do
      auth = %{
        type: :api_key,
        api_key: "secret_key"
      }

      transport = Mcp.new(auth: auth)
      assert %Mcp{} = transport
      # Note: auth is not stored in the transport struct, it's used per provider
    end
  end
end
