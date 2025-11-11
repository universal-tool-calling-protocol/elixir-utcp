# examples/webrtc_example.exs
#
# This example demonstrates WebRTC peer-to-peer communication in ExUtcp.
# It shows how to establish WebRTC connections, exchange signaling, and call tools over data channels.
#
# To run this example:
# elixir examples/webrtc_example.exs
#
# Note: This example requires a WebRTC signaling server to be running.
# For testing purposes, you can use a local signaling server or a public one.

alias ExUtcp.{Client, Providers}

# Start the ExUtcp application
{:ok, _} = Application.ensure_all_started(:ex_utcp)

IO.puts "=== ExUtcp WebRTC Transport Example ==="
IO.puts ""

# 1. Start the client
IO.puts "1. Starting UTCP client..."
{:ok, client} = Client.start_link()
IO.puts "✅ UTCP client started"

# 2. Create a WebRTC provider
IO.puts "\n2. Creating WebRTC provider..."

provider = Providers.new_webrtc_provider(
  name: "webrtc_peer",
  peer_id: "peer_#{:rand.uniform(10000)}",
  signaling_server: "wss://signaling.example.com",
  ice_servers: [
    # Public Google STUN servers
    %{urls: ["stun:stun.l.google.com:19302"]},
    %{urls: ["stun:stun1.l.google.com:19302"]},

    # Example TURN server configuration (replace with your own)
    # %{
    #   urls: ["turn:turn.example.com:3478"],
    #   username: "your_username",
    #   credential: "your_password"
    # }
  ],
  timeout: 30_000,
  tools: [
    %{
      name: "echo",
      description: "Echo tool that returns the input",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "message" => %{"type" => "string", "description" => "Message to echo"}
        }
      }
    },
    %{
      name: "calculate",
      description: "Simple calculator tool",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "operation" => %{"type" => "string", "description" => "Operation: add, subtract, multiply, divide"},
          "a" => %{"type" => "number", "description" => "First number"},
          "b" => %{"type" => "number", "description" => "Second number"}
        }
      }
    }
  ]
)

IO.puts "✅ WebRTC provider created"
IO.puts "   Peer ID: #{provider.peer_id}"
IO.puts "   Signaling Server: #{provider.signaling_server}"
IO.puts "   ICE Servers: #{length(provider.ice_servers)}"
IO.puts "   Tools: #{length(provider.tools)}"

# 3. Register the WebRTC provider
IO.puts "\n3. Registering WebRTC provider..."

case Client.register_tool_provider(client, provider) do
  {:ok, tools} ->
    IO.puts "✅ WebRTC provider registered with #{length(tools)} tools"

    Enum.each(tools, fn tool ->
      IO.puts "   - #{tool.name}: #{tool.definition.description}"
    end)

  {:error, reason} ->
    IO.puts "❌ Failed to register WebRTC provider: #{inspect(reason)}"
    IO.puts "   Note: WebRTC requires a signaling server to be running"
end

# 4. Demonstrate WebRTC concepts
IO.puts "\n4. WebRTC Connection Process:"
IO.puts "   1. Connect to signaling server"
IO.puts "   2. Create peer connection with ICE configuration"
IO.puts "   3. Create data channel for tool communication"
IO.puts "   4. Generate and exchange SDP offer/answer"
IO.puts "   5. Exchange ICE candidates for NAT traversal"
IO.puts "   6. Establish peer-to-peer connection"
IO.puts "   7. Send tool calls over data channel"
IO.puts "   8. Receive results over data channel"

# 5. Example tool call (would work with real peer)
IO.puts "\n5. Example WebRTC tool call (requires real peer):"
IO.puts """
# Call a tool over WebRTC
result = Client.call_tool(client, "webrtc_peer:echo", %{
  "message" => "Hello from WebRTC!"
})

case result do
  {:ok, response} ->
    IO.puts "Tool result: \#{inspect(response)}"
  {:error, reason} ->
    IO.puts "Tool call failed: \#{inspect(reason)}"
end
"""

# 6. Example streaming (would work with real peer)
IO.puts "\n6. Example WebRTC streaming (requires real peer):"
IO.puts """
# Stream results over WebRTC
{:ok, stream_result} = Client.call_tool_stream(client, "webrtc_peer:process_data", %{
  "data" => "large_dataset"
})

stream_result.data
|> Stream.each(fn chunk ->
  IO.puts "Received chunk: \#{inspect(chunk)}"
end)
|> Stream.run()
"""

# 7. WebRTC advantages
IO.puts "\n7. WebRTC Transport Advantages:"
IO.puts "   ✅ Peer-to-peer: No central server required after connection"
IO.puts "   ✅ Low latency: Direct communication between peers"
IO.puts "   ✅ NAT traversal: Works behind firewalls with STUN/TURN"
IO.puts "   ✅ Secure: DTLS encryption for all data"
IO.puts "   ✅ Efficient: Binary data channels with flow control"
IO.puts "   ✅ Scalable: Reduces server infrastructure requirements"

# 8. Use cases
IO.puts "\n8. WebRTC Use Cases:"
IO.puts "   • Device-to-device tool calling (IoT, mobile apps)"
IO.puts "   • Real-time collaborative tools"
IO.puts "   • Low-latency gaming and simulations"
IO.puts "   • Private peer-to-peer data processing"
IO.puts "   • Distributed computing without central coordination"
IO.puts "   • Browser-to-server tool calling (with WebRTC in browser)"

# 9. Configuration tips
IO.puts "\n9. Configuration Tips:"
IO.puts "   • Use STUN servers for NAT traversal (free public servers available)"
IO.puts "   • Use TURN servers for restrictive networks (requires hosting)"
IO.puts "   • Configure signaling server for peer discovery"
IO.puts "   • Set appropriate timeouts for connection establishment"
IO.puts "   • Use multiple ICE servers for redundancy"
IO.puts "   • Consider security implications of peer-to-peer connections"

# 10. Signaling server requirements
IO.puts "\n10. Signaling Server Requirements:"
IO.puts "   • WebSocket server for SDP exchange"
IO.puts "   • Support for offer/answer messages"
IO.puts "   • ICE candidate relay between peers"
IO.puts "   • Peer discovery and matching"
IO.puts "   • Optional: Authentication and authorization"
IO.puts "   • Optional: Room/channel management"

IO.puts "\n=== WebRTC Example Complete ==="

IO.puts """

For a complete WebRTC setup, you'll need:

1. Signaling Server:
   - WebSocket server for peer coordination
   - Can use libraries like Phoenix Channels or custom implementation
   - Example: https://github.com/elixir-webrtc/ex_webrtc/tree/master/examples

2. STUN/TURN Servers:
   - STUN: Use public servers (Google, Twilio, etc.)
   - TURN: Host your own or use services like Twilio, Xirsys
   - coturn is a popular open-source TURN server

3. Client Implementation:
   - Browser: Use WebRTC JavaScript API
   - Native: Use ex_webrtc or platform-specific libraries
   - Mobile: Use WebRTC native libraries

4. Security Considerations:
   - Validate peer identities through signaling
   - Use authentication for signaling server
   - Consider data encryption beyond DTLS
   - Implement rate limiting and abuse prevention

For more information:
- ExWebRTC: https://hexdocs.pm/ex_webrtc
- WebRTC Specification: https://www.w3.org/TR/webrtc/
- ICE/STUN/TURN: https://webrtc.org/getting-started/turn-server
"""

# Cleanup
GenServer.stop(client)

IO.puts "Example completed!"

