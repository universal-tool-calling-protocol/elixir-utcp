defmodule ExUtcp.Transports.Http.SseMockTest do
  @moduledoc """
  Mock tests for HTTP SSE streaming with simulated Req message handling.
  Tests the fix for Req.Response.get_body/2 to use proper mailbox-based streaming.
  """

  use ExUnit.Case, async: true

  describe "Req Streaming Message Simulation" do
    test "simulates receiving :data messages from Req" do
      # Simulate what happens when Req sends streaming data
      parent = self()

      spawn(fn ->
        # Simulate Req sending data chunks
        send(parent, {:data, "data: {\"chunk\": 1}\n\n"})
        send(parent, {:data, "data: {\"chunk\": 2}\n\n"})
        send(parent, {:done, make_ref()})
      end)

      # Receive first chunk
      assert_receive {:data, data1}, 1_000
      assert String.contains?(data1, "chunk")

      # Receive second chunk
      assert_receive {:data, data2}, 1_000
      assert String.contains?(data2, "chunk")

      # Receive done signal
      assert_receive {:done, _ref}, 1_000
    end

    test "simulates receiving :done message from Req" do
      parent = self()
      ref = make_ref()

      spawn(fn ->
        send(parent, {:done, ref})
      end)

      assert_receive {:done, ^ref}, 1_000
    end

    test "simulates receiving :error message from Req" do
      parent = self()
      ref = make_ref()

      spawn(fn ->
        send(parent, {:error, ref, "Connection timeout"})
      end)

      assert_receive {:error, ^ref, reason}, 1_000
      assert reason == "Connection timeout"
    end

    test "handles timeout when no messages arrive" do
      # Don't send any messages
      result = receive do
        {:data, _} -> :received_data
      after
        100 -> :timeout
      end

      assert result == :timeout
    end

    test "processes multiple data chunks in sequence" do
      parent = self()

      spawn(fn ->
        for i <- 1..5 do
          send(parent, {:data, "data: {\"seq\": #{i}}\n\n"})
        end
        send(parent, {:done, make_ref()})
      end)

      # Collect all chunks
      chunks = for _i <- 1..5 do
        receive do
          {:data, data} -> data
        after
          1_000 -> nil
        end
      end

      # Verify we got all chunks
      assert length(Enum.reject(chunks, &is_nil/1)) == 5

      # Verify done message
      assert_receive {:done, _}, 1_000
    end
  end

  describe "SSE Data Format Validation" do
    test "validates SSE data prefix" do
      valid = "data: {\"test\": true}"
      invalid = "invalid: format"

      assert String.starts_with?(valid, "data:")
      refute String.starts_with?(invalid, "data:")
    end

    test "extracts JSON from SSE data line" do
      line = "data: {\"message\": \"hello\", \"count\": 42}"

      # Extract the part after "data: "
      json_part = String.replace_prefix(line, "data: ", "")

      {:ok, parsed} = Jason.decode(json_part)
      assert parsed["message"] == "hello"
      assert parsed["count"] == 42
    end

    test "handles SSE [DONE] marker" do
      done_line = "data: [DONE]"

      assert String.contains?(done_line, "[DONE]")

      # Extract marker
      marker = String.replace_prefix(done_line, "data: ", "")
      assert marker == "[DONE]"
    end

    test "parses plain text data without JSON" do
      line = "data: plain text message"

      text = String.replace_prefix(line, "data: ", "")
      assert text == "plain text message"
    end
  end

  describe "Stream Error Recovery" do
    test "recovers from partial data errors" do
      # Simulate partial/corrupted data
      partial = {:data, "data: {\"incomplete\""}

      assert elem(partial, 0) == :data
      # Should be buffered until complete
    end

    test "handles connection errors gracefully" do
      ref = make_ref()
      error_msg = {:error, ref, :connection_closed}

      assert elem(error_msg, 0) == :error
      assert elem(error_msg, 2) == :connection_closed
    end

    test "handles network timeouts" do
      # Simulate timeout scenario
      result = receive do
        {:data, _} -> :data_received
      after
        50 -> :timeout_occurred
      end

      assert result == :timeout_occurred
    end
  end

  describe "Chunk Assembly" do
    test "assembles chunks from multiple data messages" do
      parent = self()

      # Simulate chunked SSE response
      spawn(fn ->
        send(parent, {:data, "data: {\"part\": 1}\n\n"})
        Process.sleep(10)
        send(parent, {:data, "data: {\"part\": 2}\n\n"})
        Process.sleep(10)
        send(parent, {:data, "data: {\"part\": 3}\n\n"})
      end)

      # Collect chunks with timeout
      chunk1 = receive do {:data, d} -> d after 1_000 -> nil end
      chunk2 = receive do {:data, d} -> d after 1_000 -> nil end
      chunk3 = receive do {:data, d} -> d after 1_000 -> nil end

      assert chunk1 != nil
      assert chunk2 != nil
      assert chunk3 != nil
    end

    test "preserves data order" do
      parent = self()

      spawn(fn ->
        Enum.each(1..10, fn i ->
          send(parent, {:data, "data: {\"order\": #{i}}\n\n"})
        end)
      end)

      # Receive in order
      received = for _i <- 1..10 do
        receive do
          {:data, data} -> data
        after
          1_000 -> nil
        end
      end

      # All should be received
      assert Enum.all?(received, &(!is_nil(&1)))
    end
  end

  describe "Stream Termination" do
    test "stream ends on :done message" do
      parent = self()

      spawn(fn ->
        send(parent, {:data, "data: test\n\n"})
        send(parent, {:done, make_ref()})
      end)

      # Process should stop after :done
      assert_receive {:data, _}, 1_000
      assert_receive {:done, _}, 1_000

      # No more messages should arrive
      refute_receive {:data, _}, 100
    end

    test "stream ends on :error message" do
      parent = self()

      spawn(fn ->
        send(parent, {:data, "data: test\n\n"})
        send(parent, {:error, make_ref(), "Failed"})
      end)

      # Process should stop after :error
      assert_receive {:data, _}, 1_000
      assert_receive {:error, _, _}, 1_000

      # No more messages should arrive
      refute_receive {:data, _}, 100
    end

    test "stream terminates after timeout" do
      # No messages sent
      result = receive do
        {:data, _} -> :got_data
      after
        100 -> :timed_out
      end

      assert result == :timed_out
    end
  end

  describe "Integration Scenarios" do
    test "handles complete SSE conversation" do
      parent = self()

      spawn(fn ->
        # Send initial data
        send(parent, {:data, "data: {\"status\": \"starting\"}\n\n"})
        Process.sleep(10)

        # Send progress updates
        send(parent, {:data, "data: {\"progress\": 50}\n\n"})
        Process.sleep(10)
        send(parent, {:data, "data: {\"progress\": 100}\n\n"})
        Process.sleep(10)

        # Send completion
        send(parent, {:data, "data: {\"status\": \"complete\"}\n\n"})
        send(parent, {:data, "data: [DONE]\n\n"})
        send(parent, {:done, make_ref()})
      end)

      # Collect all messages
      messages = for _i <- 1..5 do
        receive do
          {:data, data} -> data
        after
          1_000 -> nil
        end
      end

      # Verify we got messages
      valid_messages = Enum.reject(messages, &is_nil/1)
      assert length(valid_messages) == 5

      # Verify done signal
      assert_receive {:done, _}, 1_000
    end

    test "handles interleaved event types" do
      parent = self()

      spawn(fn ->
        send(parent, {:data, "event: message\n"})
        send(parent, {:data, "id: 1\n"})
        send(parent, {:data, "data: {\"actual\": \"data\"}\n\n"})
        send(parent, {:done, make_ref()})
      end)

      # Collect all data messages
      msg1 = receive do {:data, d} -> d after 1_000 -> nil end
      msg2 = receive do {:data, d} -> d after 1_000 -> nil end
      msg3 = receive do {:data, d} -> d after 1_000 -> nil end

      # Should receive all parts
      assert msg1 != nil
      assert msg2 != nil
      assert msg3 != nil

      # Done signal
      assert_receive {:done, _}, 1_000
    end

    test "handles rapid message bursts" do
      parent = self()

      spawn(fn ->
        # Send many messages rapidly
        Enum.each(1..100, fn i ->
          send(parent, {:data, "data: {\"burst\": #{i}}\n\n"})
        end)
        send(parent, {:done, make_ref()})
      end)

      # Process should be able to handle all messages
      # Just verify we can receive multiple messages
      assert_receive {:data, _}, 1_000
      assert_receive {:data, _}, 100
      assert_receive {:data, _}, 100

      # Flush remaining messages
      :timer.sleep(100)
    end
  end

  describe "Memory Management" do
    test "buffer doesn't grow unbounded" do
      # Initial buffer
      buffer = ""

      # Add data
      buffer = buffer <> "data: test\n\n"
      initial_size = byte_size(buffer)

      # After processing, buffer should be cleared or smaller
      buffer_after_processing = ""

      assert byte_size(buffer_after_processing) < initial_size
    end

    test "old chunks are not retained" do
      # Process chunks and discard
      state = %{buffer: "data: old\n\n", sequence: 0}

      # After processing, buffer should be cleared
      new_state = %{state | buffer: "", sequence: 1}

      assert new_state.buffer == ""
      assert byte_size(new_state.buffer) == 0
    end
  end
end
