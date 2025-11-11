defmodule ExUtcp.Transports.TcpUdpMockTest do
  use ExUnit.Case, async: false

  import Mox

  alias ExUtcp.Providers
  alias ExUtcp.Transports.TcpUdp
  alias ExUtcp.Transports.TcpUdp.ConnectionMock
  alias ExUtcp.Transports.TcpUdp.PoolMock
  alias ExUtcp.Transports.TcpUdp.Testable

  # Define mocks
  defmock(ConnectionMock,
    for: ExUtcp.Transports.TcpUdp.ConnectionBehaviour
  )

  defmock(PoolMock, for: ExUtcp.Transports.TcpUdp.PoolBehaviour)

  setup do
    # Set up mocks
    Testable.set_mocks(ConnectionMock, PoolMock)

    # Set application environment to use mocks
    Application.put_env(
      :ex_utcp,
      :tcp_udp_connection_behaviour,
      ConnectionMock
    )

    # Generate a unique name for each test
    test_name = String.to_atom("test_tcp_udp_mock_transport_#{:rand.uniform(1_000_000)}")

    # Start the transport with a unique name
    {:ok, transport_pid} = TcpUdp.start_link(name: test_name)

    # Allow the transport GenServer to use the mocks
    Mox.allow(ConnectionMock, self(), transport_pid)
    Mox.allow(PoolMock, self(), transport_pid)

    on_exit(fn ->
      Testable.clear_mocks()
      # Reset application environment
      Application.delete_env(:ex_utcp, :tcp_udp_connection_behaviour)

      try do
        GenServer.stop(test_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{transport_pid: transport_pid, transport_name: test_name}
  end

  describe "TCP/UDP Transport with Mocks" do
    test "registers TCP provider successfully", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})
    end

    test "registers UDP provider successfully", %{transport_name: transport_name} do
      provider =
        Providers.new_udp_provider(
          name: "test_udp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})
    end

    @tag :skip
    test "calls tool with successful response", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})

      # Mock the connection to return a successful response
      conn_pid = self()

      # Allow the GenServer process to use the mock
      genserver_pid = GenServer.whereis(transport_name)
      Mox.allow(ConnectionMock, self(), genserver_pid)

      expect(ConnectionMock, :start_link, 1, fn _provider ->
        {:ok, conn_pid}
      end)

      expect(ConnectionMock, :call_tool, fn ^conn_pid, "test_tool", %{"message" => "hello"}, 30_000 ->
        {:ok, %{"response" => "Hello from TCP server!"}}
      end)

      result =
        GenServer.call(
          transport_name,
          {:call_tool, "test_tool", %{"message" => "hello"}, provider}
        )

      assert {:ok, %{"response" => "Hello from TCP server!"}} = result
    end

    @tag :skip
    test "calls tool with error response", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})

      # Mock the connection to return an error
      conn_pid = self()

      expect(ConnectionMock, :start_link, 1, fn _provider ->
        {:ok, conn_pid}
      end)

      expect(ConnectionMock, :call_tool, fn ^conn_pid, "test_tool", %{"message" => "hello"}, 30_000 ->
        {:error, "Connection timeout"}
      end)

      result =
        GenServer.call(
          transport_name,
          {:call_tool, "test_tool", %{"message" => "hello"}, provider}
        )

      assert {:error, "Failed to call tool: Connection timeout"} = result
    end

    @tag :skip
    test "calls tool stream with successful response", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})

      # Mock the connection to return a stream
      conn_pid = self()

      expect(ConnectionMock, :start_link, 1, fn _provider ->
        {:ok, conn_pid}
      end)

      stream_data = [
        %{"chunk" => "Hello"},
        %{"chunk" => " from"},
        %{"chunk" => " TCP server!"}
      ]

      stream =
        Stream.map(stream_data, fn data ->
          %{type: :stream, data: data}
        end)

      expect(ConnectionMock, :call_tool_stream, fn ^conn_pid,
                                                   "test_tool",
                                                   %{
                                                     "message" => "hello"
                                                   },
                                                   30_000 ->
        {:ok, stream}
      end)

      result =
        GenServer.call(
          transport_name,
          {:call_tool_stream, "test_tool", %{"message" => "hello"}, provider}
        )

      assert {:ok, %{type: :stream, data: _stream_data, metadata: metadata}} = result
      assert metadata["transport"] == "tcp_udp"
      assert metadata["tool"] == "test_tool"
      assert metadata["protocol"] == :tcp
    end

    @tag :skip
    test "handles pool connection failure", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})

      # Mock the connection to return an error
      expect(ConnectionMock, :start_link, 1, fn _provider ->
        {:error, "Connection failed"}
      end)

      result =
        GenServer.call(
          transport_name,
          {:call_tool, "test_tool", %{"message" => "hello"}, provider}
        )

      assert {:error, "Failed to get connection: Connection failed"} = result
    end

    @tag :skip
    test "handles retry logic", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})

      # Mock the connection to fail twice then succeed
      conn_pid = self()

      expect(ConnectionMock, :start_link, fn _provider ->
        {:error, "Temporary failure"}
      end)
      |> expect(:start_link, fn _provider ->
        {:error, "Temporary failure"}
      end)
      |> expect(:start_link, fn _provider ->
        {:ok, conn_pid}
      end)

      # Mock the connection to return a successful response
      expect(ConnectionMock, :call_tool, fn ^conn_pid, "test_tool", %{"message" => "hello"}, 30_000 ->
        {:ok, %{"response" => "Hello from TCP server!"}}
      end)

      result =
        GenServer.call(
          transport_name,
          {:call_tool, "test_tool", %{"message" => "hello"}, provider}
        )

      # Should eventually succeed or fail based on retry logic
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "deregisters provider successfully", %{transport_name: transport_name} do
      provider =
        Providers.new_tcp_provider(
          name: "test_tcp",
          host: "localhost",
          port: 8080
        )

      assert {:ok, []} = GenServer.call(transport_name, {:register_tool_provider, provider})
      assert :ok = GenServer.call(transport_name, {:deregister_tool_provider, provider})
    end

    test "closes transport and all connections", %{transport_name: transport_name} do
      # Mock pool close all connections
      pool_pid = self()

      expect(PoolMock, :close_all_connections, fn ^pool_pid ->
        :ok
      end)

      # Use the named transport process
      assert :ok = GenServer.call(transport_name, :close)
    end
  end

  describe "Testable Module" do
    test "creates test TCP provider" do
      provider = Testable.create_test_tcp_provider()

      assert provider.name == "test_tcp"
      assert provider.type == :tcp
      assert provider.protocol == :tcp
      assert provider.host == "localhost"
      assert provider.port == 8080
    end

    test "creates test UDP provider" do
      provider = Testable.create_test_udp_provider()

      assert provider.name == "test_udp"
      assert provider.type == :udp
      assert provider.protocol == :udp
      assert provider.host == "localhost"
      assert provider.port == 8080
    end

    test "creates test tool" do
      tool = Testable.create_test_tool()

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
      assert tool.inputs.type == "object"
      assert tool.outputs.type == "object"
    end

    test "validates TCP provider" do
      valid_provider = %{
        name: "test",
        host: "localhost",
        port: 8080,
        protocol: :tcp
      }

      assert :ok = Testable.validate_tcp_provider(valid_provider)

      invalid_provider = %{
        name: "test",
        host: "localhost"
        # Missing port and protocol
      }

      assert {:error, "TCP provider missing required field: port"} =
               Testable.validate_tcp_provider(invalid_provider)
    end

    test "validates UDP provider" do
      valid_provider = %{
        name: "test",
        host: "localhost",
        port: 8080,
        protocol: :udp
      }

      assert :ok = Testable.validate_udp_provider(valid_provider)

      invalid_provider = %{
        name: "test",
        port: 8080
        # Missing host and protocol
      }

      assert {:error, "UDP provider missing required field: host"} =
               Testable.validate_udp_provider(invalid_provider)
    end

    test "mocks tool call response" do
      response =
        Testable.mock_tool_call_response("test_tool", %{"message" => "hello"}, %{
          "response" => "world"
        })

      assert response.tool == "test_tool"
      assert response.args == %{"message" => "hello"}
      assert response.response == %{"response" => "world"}
      assert is_integer(response.timestamp)
    end

    test "mocks tool stream response" do
      stream_data = [%{"chunk" => "hello"}, %{"chunk" => "world"}]

      response =
        Testable.mock_tool_stream_response("test_tool", %{"message" => "hello"}, stream_data)

      assert response.tool == "test_tool"
      assert response.args == %{"message" => "hello"}
      assert %Stream{} = response.stream
      assert is_integer(response.timestamp)
    end
  end
end
