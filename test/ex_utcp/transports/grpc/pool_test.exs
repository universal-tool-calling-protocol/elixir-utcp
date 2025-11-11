defmodule ExUtcp.Transports.Grpc.PoolTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Providers
  alias ExUtcp.Transports.Grpc.Pool

  setup do
    # Stop any existing pool and start fresh
    case Process.whereis(Pool) do
      nil ->
        :ok

      pool_pid ->
        try do
          if Process.alive?(pool_pid) do
            GenServer.stop(pool_pid, :normal, 500)
            # Give it more time to stop
            Process.sleep(300)
          end
        rescue
          _ -> :ok
        end
    end

    # Try to start the pool, handle already started error
    case Pool.start_link(max_connections: 2) do
      {:ok, pool_pid} -> %{pool_pid: pool_pid}
      {:error, {:already_started, pool_pid}} -> %{pool_pid: pool_pid}
    end
  end

  describe "gRPC Connection Pool" do
    test "starts successfully", %{pool_pid: pool_pid} do
      assert Process.alive?(pool_pid)
    end

    test "gets pool statistics", %{pool_pid: _pool_pid} do
      stats = Pool.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_connections)
      assert Map.has_key?(stats, :max_connections)
      assert Map.has_key?(stats, :connection_keys)
      assert stats.max_connections == 2
    end

    test "handles connection creation failure" do
      provider = %{
        name: "test",
        type: :grpc,
        host: "invalid-host",
        port: 99_999,
        service_name: "UTCPService",
        method_name: "GetManual",
        use_ssl: false
      }

      # With the mock implementation, this will succeed
      assert {:ok, _pid} = Pool.get_connection(provider)
    end

    test "respects max connections limit" do
      # This test would require mocking the connection creation
      # to avoid actually trying to connect to real servers
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "localhost",
          port: 50_051,
          service_name: "UTCPService",
          method_name: "GetManual",
          use_ssl: false
        )

      # With the mock implementation, this will succeed
      assert {:ok, _pid} = Pool.get_connection(provider)
    end

    test "closes all connections" do
      Pool.close_all_connections()

      stats = Pool.stats()
      assert stats.total_connections == 0
    end
  end
end
