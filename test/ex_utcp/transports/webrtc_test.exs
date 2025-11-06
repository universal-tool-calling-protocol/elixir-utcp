defmodule ExUtcp.Transports.WebRTCTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Providers
  alias ExUtcp.Transports.WebRTC

  @moduletag :integration

  describe "WebRTC Transport" do
    test "creates new transport" do
      transport = WebRTC.new()

      assert %WebRTC{} = transport
      assert transport.signaling_server == "wss://signaling.example.com"
      assert is_list(transport.ice_servers)
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      transport =
        WebRTC.new(
          signaling_server: "wss://custom.signaling.com",
          connection_timeout: 60_000,
          ice_servers: [%{urls: ["stun:stun.custom.com:19302"]}]
        )

      assert transport.signaling_server == "wss://custom.signaling.com"
      assert transport.connection_timeout == 60_000
      assert length(transport.ice_servers) == 1
    end

    test "returns correct transport name" do
      assert WebRTC.transport_name() == "webrtc"
    end

    test "supports streaming" do
      assert WebRTC.supports_streaming?() == true
    end

    test "validates provider type" do
      valid_provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "peer_123",
          signaling_server: "wss://signaling.example.com"
        )

      invalid_provider = %{
        name: "test_http",
        type: :http,
        url: "http://api.example.com"
      }

      # Valid provider should work (may fail without real signaling server)
      assert valid_provider.type == :webrtc

      # Invalid provider should be rejected
      assert {:error, _reason} = WebRTC.register_tool_provider(invalid_provider)
    end
  end

  describe "WebRTC Provider Creation" do
    test "creates WebRTC provider with required fields" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "peer_123"
        )

      assert provider.name == "test_webrtc"
      assert provider.type == :webrtc
      assert provider.peer_id == "peer_123"
      assert provider.signaling_server == "wss://signaling.example.com"
      assert is_list(provider.ice_servers)
      assert provider.timeout == 30_000
    end

    test "creates WebRTC provider with custom signaling server" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          signaling_server: "wss://my-signaling.com"
        )

      assert provider.signaling_server == "wss://my-signaling.com"
    end

    test "creates WebRTC provider with custom ICE servers" do
      custom_ice_servers = [
        %{urls: ["stun:stun.custom.com:19302"]},
        %{
          urls: ["turn:turn.custom.com:3478"],
          username: "user",
          credential: "pass"
        }
      ]

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          ice_servers: custom_ice_servers
        )

      assert provider.ice_servers == custom_ice_servers
      assert length(provider.ice_servers) == 2
    end

    test "creates WebRTC provider with tools" do
      tools = [
        %{name: "tool1", description: "Test tool 1"},
        %{name: "tool2", description: "Test tool 2"}
      ]

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          tools: tools
        )

      assert provider.tools == tools
      assert length(provider.tools) == 2
    end
  end

  describe "WebRTC Connection" do
    @tag :skip
    test "establishes peer connection" do
      # This test requires a real signaling server and peer
      # Skipped for unit tests, would be run in integration environment

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "remote_peer",
          signaling_server: "wss://signaling.example.com"
        )

      # Would test actual connection establishment
      assert provider.type == :webrtc
    end

    @tag :skip
    test "exchanges ICE candidates" do
      # This test requires actual peer connection
      # Skipped for unit tests

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "remote_peer"
        )

      assert provider.type == :webrtc
    end

    @tag :skip
    test "creates data channel" do
      # This test requires actual peer connection
      # Skipped for unit tests

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "remote_peer"
        )

      assert provider.type == :webrtc
    end
  end

  describe "WebRTC Tool Calling" do
    @tag :skip
    test "calls tool over data channel" do
      # This test requires actual peer connection and data channel
      # Skipped for unit tests

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "remote_peer",
          tools: [%{name: "test_tool", description: "Test tool"}]
        )

      # Would test actual tool call over WebRTC
      assert provider.type == :webrtc
    end

    @tag :skip
    test "streams tool results over data channel" do
      # This test requires actual peer connection
      # Skipped for unit tests

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "remote_peer"
        )

      assert provider.type == :webrtc
    end

    @tag :skip
    test "handles connection errors" do
      # This test requires actual peer connection
      # Skipped for unit tests

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          peer_id: "nonexistent_peer"
        )

      assert provider.type == :webrtc
    end
  end

  describe "WebRTC Configuration" do
    test "uses default STUN servers" do
      provider = Providers.new_webrtc_provider(name: "test_webrtc")

      assert is_list(provider.ice_servers)
      refute Enum.empty?(provider.ice_servers)

      # Should have Google STUN server by default
      stun_server = hd(provider.ice_servers)
      assert Map.has_key?(stun_server, :urls)
      assert is_list(stun_server.urls)
    end

    test "supports custom TURN servers" do
      turn_servers = [
        %{
          urls: ["turn:turn.example.com:3478"],
          username: "testuser",
          credential: "testpass"
        }
      ]

      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          ice_servers: turn_servers
        )

      assert provider.ice_servers == turn_servers
      turn_server = hd(provider.ice_servers)
      assert Map.has_key?(turn_server, :username)
      assert Map.has_key?(turn_server, :credential)
    end

    test "configures timeout" do
      provider =
        Providers.new_webrtc_provider(
          name: "test_webrtc",
          timeout: 60_000
        )

      assert provider.timeout == 60_000
    end
  end
end
