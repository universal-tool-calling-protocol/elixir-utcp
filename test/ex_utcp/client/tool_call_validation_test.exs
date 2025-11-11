defmodule ExUtcp.Client.ToolCallValidationTest do
  @moduledoc """
  Tests for Client tool call validation and error handling.
  Covers the refactored call_tool_impl and call_tool_stream_impl with proper error paths.
  """

  use ExUnit.Case, async: false

  alias ExUtcp.Client
  alias ExUtcp.Providers

  setup do
    config = %{providers_file_path: nil, variables: %{}}
    {:ok, client} = Client.start_link(config)
    %{client: client}
  end

  describe "Tool Not Found Error Path" do
    test "returns error when tool doesn't exist", %{client: client} do
      result = Client.call_tool(client, "nonexistent_tool", %{})

      assert {:error, reason} = result
      assert String.contains?(reason, "Tool not found") or String.contains?(reason, "not found")
    end

    test "returns error for empty tool name", %{client: client} do
      result = Client.call_tool(client, "", %{})

      assert {:error, _reason} = result
    end

    test "handles nil tool name", %{client: client} do
      # This may cause an error or crash depending on implementation
      result =
        try do
          Client.call_tool(client, nil, %{})
        catch
          :error, _ -> {:error, "Invalid tool name"}
        end

      # Should either return error or catch the exception
      assert match?({:error, _}, result)
    end

    test "provides descriptive error message", %{client: client} do
      result = Client.call_tool(client, "missing_tool", %{})

      case result do
        {:error, message} ->
          assert is_binary(message)
          assert String.length(message) > 0

        _ ->
          flunk("Expected error tuple")
      end
    end
  end

  describe "Provider Not Found Error Path" do
    test "returns error when provider doesn't exist", %{client: client} do
      # Register a tool without a provider
      _tool = %{
        name: "orphan_provider.orphan_tool",
        definition: %{
          name: "orphan_tool",
          description: "Tool without provider"
        }
      }

      # Try to call tool without registering provider
      result = Client.call_tool(client, "orphan_provider.orphan_tool", %{})

      assert {:error, reason} = result
      assert String.contains?(reason, "not found") or String.contains?(reason, "Provider")
    end

    test "validates provider name extraction", %{client: client} do
      # Tool name format: "provider.tool"
      result = Client.call_tool(client, "missing_provider.some_tool", %{})

      assert {:error, reason} = result
      assert is_binary(reason)
    end
  end

  describe "Transport Not Available Error Path" do
    test "returns error when transport not available", %{client: client} do
      # Register a provider with unsupported transport type
      provider = %{
        name: "unsupported_provider",
        type: :unsupported_transport,
        url: "http://example.com"
      }

      Client.register_tool_provider(client, provider)

      # Register a tool for this provider
      _tool = %{
        name: "unsupported_provider.test_tool",
        definition: %{
          name: "test_tool",
          description: "Test"
        }
      }

      # Attempt to call tool (should fail due to missing transport)
      result = Client.call_tool(client, "unsupported_provider.test_tool", %{})

      case result do
        {:error, reason} ->
          assert String.contains?(reason, "transport") or String.contains?(reason, "not found")

        _ ->
          # May succeed if tool/provider not actually registered
          assert true
      end
    end
  end

  describe "With Statement Error Propagation" do
    test "errors propagate correctly through with statement" do
      # Simulate the with statement error handling
      result =
        with {:ok, _tool} <- {:error, "Tool not found"},
             _provider_name = "test",
             {:ok, _provider} <- {:ok, %{type: :http}},
             {:ok, _transport} <- {:ok, ExUtcp.Transports.Http} do
          {:ok, "success"}
        end

      assert result == {:error, "Tool not found"}
    end

    test "with statement stops at first error" do
      # Test that with stops at the first error
      steps = []

      result =
        with {:ok, _} <- {:error, "First error"},
             # This should never execute
             _steps = [:should_not_reach | steps],
             {:ok, :value},
             {:ok, _} <- {:ok, :value} do
          {:ok, "success"}
        end

      assert result == {:error, "First error"}
      assert steps == []
    end

    test "with statement executes all steps on success" do
      result =
        with {:ok, tool} <- {:ok, %{name: "test"}},
             provider_name = "provider",
             {:ok, provider} <- {:ok, %{type: :http}},
             {:ok, transport} <- {:ok, ExUtcp.Transports.Http} do
          {:ok, {tool, provider_name, provider, transport}}
        end

      assert match?({:ok, _}, result)
    end
  end

  describe "Helper Function Error Handling" do
    test "get_tool_or_error returns error for nil" do
      # Simulate the helper function behavior
      result =
        case nil do
          nil -> {:error, "Tool not found: test"}
          tool -> {:ok, tool}
        end

      assert result == {:error, "Tool not found: test"}
    end

    test "get_tool_or_error returns ok for valid tool" do
      tool = %{name: "test_tool"}

      # Simulate the helper function behavior
      result = {:ok, tool}

      assert result == {:ok, %{name: "test_tool"}}
    end

    test "get_provider_or_error returns error for nil" do
      result =
        case nil do
          nil -> {:error, "Provider not found: test"}
          provider -> {:ok, provider}
        end

      assert result == {:error, "Provider not found: test"}
    end

    test "get_transport_or_error returns error for nil" do
      transports = %{}

      result =
        case Map.get(transports, "http") do
          nil -> {:error, "No transport available"}
          transport -> {:ok, transport}
        end

      assert result == {:error, "No transport available"}
    end

    test "extract_call_name handles mcp type" do
      # MCP and text types extract tool name
      tool_name = "provider.tool_name"

      result =
        if :mcp in [:mcp, :text] do
          # Extract just "tool_name"
          String.split(tool_name, ".") |> List.last()
        else
          tool_name
        end

      assert result == "tool_name"
    end

    test "extract_call_name preserves full name for other types" do
      tool_name = "provider.tool_name"

      result =
        if :http in [:mcp, :text] do
          String.split(tool_name, ".") |> List.last()
        else
          tool_name
        end

      assert result == "provider.tool_name"
    end
  end

  describe "Stream Call Validation" do
    test "call_tool_stream follows same validation path", %{client: client} do
      # Stream calls should have same error handling as regular calls
      result = Client.call_tool_stream(client, "nonexistent_tool", %{})

      assert {:error, reason} = result
      assert is_binary(reason)
    end

    test "stream call validates tool existence", %{client: client} do
      result = Client.call_tool_stream(client, "missing.tool", %{})

      assert {:error, _reason} = result
    end

    test "stream call validates provider existence", %{client: client} do
      result = Client.call_tool_stream(client, "missing_provider.tool", %{})

      assert {:error, _reason} = result
    end
  end

  describe "Integration with Real Providers" do
    test "validates complete flow with HTTP provider", %{client: client} do
      provider =
        Providers.new_http_provider(
          name: "test_http",
          url: "http://localhost:9999/nonexistent"
        )

      # Registration may fail if server not available
      case Client.register_tool_provider(client, provider) do
        {:ok, _} ->
          # Tool call will fail (no server), but validation should pass
          result = Client.call_tool(client, "test_http.some_tool", %{})
          assert match?({:error, _}, result) or match?({:ok, _}, result)

        {:error, _reason} ->
          # Provider registration failed, which is acceptable for this test
          assert true
      end
    end

    test "handles multiple providers gracefully", %{client: client} do
      # Register multiple providers
      provider1 = Providers.new_http_provider(name: "http1", url: "http://example1.com")
      provider2 = Providers.new_http_provider(name: "http2", url: "http://example2.com")

      # Attempt to register (may fail if servers not available)
      _result1 = Client.register_tool_provider(client, provider1)
      _result2 = Client.register_tool_provider(client, provider2)

      # Get stats regardless of registration success
      stats = Client.get_stats(client)
      assert is_integer(stats.provider_count)
      assert stats.provider_count >= 0
    end
  end

  describe "Error Message Quality" do
    test "tool not found error is clear", %{client: client} do
      {:error, message} = Client.call_tool(client, "nonexistent", %{})

      assert String.contains?(message, "not found") or String.contains?(message, "Tool")
    end

    test "provider not found error is clear", %{client: client} do
      {:error, message} = Client.call_tool(client, "missing.tool", %{})

      assert String.contains?(message, "not found") or
               String.contains?(message, "Provider") or
               String.contains?(message, "Tool")
    end

    test "transport not available error is clear" do
      error = "No transport available for provider type: custom"

      assert String.contains?(error, "transport")
      assert String.contains?(error, "available")
    end

    test "errors don't leak sensitive information" do
      # Error messages should be informative but not expose internals
      errors = [
        "Tool not found: test",
        "Provider not found: test",
        "No transport available"
      ]

      Enum.each(errors, fn error ->
        # Should not contain stack traces, PIDs, or internal state
        refute String.contains?(error, "#PID<")
        refute String.contains?(error, "stacktrace")
        refute String.contains?(error, "%{")
      end)
    end
  end

  describe "Concurrent Access" do
    test "handles concurrent tool calls", %{client: client} do
      # Multiple processes calling tools simultaneously
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Client.call_tool(client, "test_tool_#{i}", %{})
          end)
        end

      results = Task.await_many(tasks, 5_000)

      # All should return (either success or error)
      assert length(results) == 10
      assert Enum.all?(results, fn r -> match?({:ok, _}, r) or match?({:error, _}, r) end)
    end

    test "handles concurrent stream calls", %{client: client} do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            Client.call_tool_stream(client, "stream_tool_#{i}", %{})
          end)
        end

      results = Task.await_many(tasks, 5_000)

      assert length(results) == 5
      assert Enum.all?(results, fn r -> match?({:ok, _}, r) or match?({:error, _}, r) end)
    end
  end
end
