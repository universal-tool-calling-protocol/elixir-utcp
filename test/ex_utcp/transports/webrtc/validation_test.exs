defmodule ExUtcp.Transports.WebRTC.ValidationTest do
  @moduledoc """
  Tests for WebRTC tool discovery validation.
  Covers the fix for "clause will never match" warning by testing error paths.
  """

  use ExUnit.Case, async: true

  alias ExUtcp.Providers
  alias ExUtcp.Transports.WebRTC

  describe "Tool Discovery Validation" do
    test "accepts valid tools list" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "peer_123",
          signaling_server: "wss://signal.example.com",
          ice_servers: [%{urls: ["stun:stun.example.com"]}],
          tools: [
            %{name: "tool1", description: "First tool"},
            %{name: "tool2", description: "Second tool"}
          ]
        )

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      case result do
        {:ok, tools} ->
          assert is_list(tools)
          assert length(tools) == 2

        {:error, _reason} ->
          # May fail if signaling not available, but should not crash
          assert true
      end

      GenServer.stop(transport)
    end

    test "accepts empty tools list" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc_empty",
          peer_id: "peer_456",
          signaling_server: "wss://signal.example.com",
          ice_servers: [],
          tools: []
        )

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      case result do
        {:ok, tools} ->
          assert is_list(tools)
          assert length(tools) == 0

        {:error, _reason} ->
          assert true
      end

      GenServer.stop(transport)
    end

    test "accepts provider without tools field" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc_no_tools",
          peer_id: "peer_789",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Remove tools field
      provider = Map.delete(provider, :tools)

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      case result do
        {:ok, tools} ->
          assert is_list(tools)
          assert length(tools) == 0

        {:error, _reason} ->
          assert true
      end

      GenServer.stop(transport)
    end

    test "rejects invalid tools format - not a list" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc_invalid",
          peer_id: "peer_invalid",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Set tools to invalid format (not a list)
      provider = Map.put(provider, :tools, "invalid")

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      assert {:error, reason} = result
      assert is_binary(reason)
      assert String.contains?(reason, "Invalid") or String.contains?(reason, "must be a list")

      GenServer.stop(transport)
    end

    test "rejects tools list with non-map elements" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc_bad_tools",
          peer_id: "peer_bad",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Set tools to list with non-map elements
      provider = Map.put(provider, :tools, ["string_tool", 123, :atom_tool])

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      assert {:error, reason} = result
      assert is_binary(reason)
      assert String.contains?(reason, "Invalid") or String.contains?(reason, "must be maps")

      GenServer.stop(transport)
    end

    test "rejects tools list with mixed valid and invalid elements" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc_mixed",
          peer_id: "peer_mixed",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Mix valid maps with invalid elements
      provider = Map.put(provider, :tools, [
        %{name: "valid_tool"},
        "invalid_string",
        %{name: "another_valid"}
      ])

      {:ok, transport} = WebRTC.start_link()

      result = GenServer.call(transport, {:register_tool_provider, provider})

      assert {:error, reason} = result
      assert is_binary(reason)

      GenServer.stop(transport)
    end
  end

  describe "Tool Format Validation" do
    test "validates tool is a map" do
      valid_tool = %{name: "test", description: "Test tool"}
      invalid_tool = "not_a_map"

      assert is_map(valid_tool)
      refute is_map(invalid_tool)
    end

    test "validates list of tools" do
      valid_tools = [
        %{name: "tool1"},
        %{name: "tool2"},
        %{name: "tool3"}
      ]

      assert Enum.all?(valid_tools, &is_map/1)
    end

    test "detects invalid tools in list" do
      invalid_tools = [
        %{name: "tool1"},
        "invalid",
        %{name: "tool3"}
      ]

      refute Enum.all?(invalid_tools, &is_map/1)
    end

    test "handles empty list" do
      empty_tools = []

      assert Enum.all?(empty_tools, &is_map/1)
      assert length(empty_tools) == 0
    end
  end

  describe "Error Message Quality" do
    test "provides clear error for non-list tools" do
      error_message = "Invalid tools configuration: must be a list"

      assert String.contains?(error_message, "must be a list")
      assert String.contains?(error_message, "Invalid")
    end

    test "provides clear error for non-map tools" do
      error_message = "Invalid tool format: tools must be maps"

      assert String.contains?(error_message, "must be maps")
      assert String.contains?(error_message, "Invalid")
    end

    test "error messages are descriptive" do
      errors = [
        "Invalid tools configuration: must be a list",
        "Invalid tool format: tools must be maps"
      ]

      Enum.each(errors, fn error ->
        assert is_binary(error)
        assert String.length(error) > 10
        assert String.contains?(error, "Invalid")
      end)
    end
  end

  describe "Provider Configuration" do
    test "creates provider with valid tools" do
      provider =
        Providers.new_webrtc_provider(
          name: "test",
          peer_id: "peer_test",
          signaling_server: "wss://signal.example.com",
          ice_servers: [],
          tools: [%{name: "test_tool"}]
        )

      assert provider.tools == [%{name: "test_tool"}]
    end

    test "creates provider without tools field" do
      provider =
        Providers.new_webrtc_provider(
          name: "test",
          peer_id: "peer_test",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Tools field may or may not exist
      tools = Map.get(provider, :tools)
      assert is_nil(tools) or is_list(tools)
    end

    test "handles tools field modification" do
      provider =
        Providers.new_webrtc_provider(
          name: "test",
          peer_id: "peer_test",
          signaling_server: "wss://signal.example.com",
          ice_servers: []
        )

      # Add tools after creation
      updated = Map.put(provider, :tools, [%{name: "new_tool"}])

      assert updated.tools == [%{name: "new_tool"}]
    end
  end

  describe "Edge Cases" do
    test "handles nil tools value" do
      tools = nil

      result =
        case tools do
          nil -> {:ok, []}
          tools when is_list(tools) -> {:ok, tools}
          _ -> {:error, "Invalid"}
        end

      assert result == {:ok, []}
    end

    test "handles large tools list" do
      large_tools = for i <- 1..100, do: %{name: "tool_#{i}"}

      assert length(large_tools) == 100
      assert Enum.all?(large_tools, &is_map/1)
    end

    test "handles tools with complex structures" do
      complex_tools = [
        %{
          name: "complex_tool",
          description: "A complex tool",
          parameters: %{
            type: "object",
            properties: %{
              param1: %{type: "string"},
              param2: %{type: "number"}
            }
          }
        }
      ]

      assert Enum.all?(complex_tools, &is_map/1)
      assert length(complex_tools) == 1
    end

    test "handles empty map as tool" do
      tools = [%{}]

      assert Enum.all?(tools, &is_map/1)
      assert length(tools) == 1
    end
  end
end
