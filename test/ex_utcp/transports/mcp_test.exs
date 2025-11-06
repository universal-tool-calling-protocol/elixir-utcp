defmodule ExUtcp.Transports.McpTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Transports.Mcp

  @moduletag :integration

  describe "MCP Transport" do
    setup do
      # Clean up any existing MCP transport
      case Process.whereis(Mcp) do
        nil ->
          :ok

        pid ->
          try do
            GenServer.stop(pid)
          rescue
            _ -> :ok
          end
      end

      # Start the MCP transport for tests that need it
      {:ok, _pid} = Mcp.start_link()
      :ok
    end

    test "creates new transport" do
      transport = Mcp.new()

      assert %Mcp{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Mcp.new(logger: logger, connection_timeout: 60_000)

      assert %Mcp{} = transport
      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "returns correct transport name" do
      assert Mcp.transport_name() == "mcp"
    end

    test "supports streaming" do
      assert Mcp.supports_streaming?() == true
    end

    test "validates provider type" do
      valid_provider = %{
        name: "test",
        type: :mcp,
        url: "http://localhost:3000/mcp",
        auth: nil
      }

      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil
      }

      # Test with valid provider
      assert {:ok, _tools} = Mcp.register_tool_provider(valid_provider)

      # Test with invalid provider type
      assert {:error, "Invalid provider type for MCP transport"} =
               Mcp.register_tool_provider(invalid_provider)
    end

    test "deregister_tool_provider always succeeds" do
      provider = %{
        name: "test",
        type: :mcp,
        url: "http://localhost:3000/mcp",
        auth: nil
      }

      assert :ok = Mcp.deregister_tool_provider(provider)
    end

    test "close always succeeds" do
      assert :ok = Mcp.close()
    end
  end
end
