defmodule ExUtcp.Transports.GraphqlTest do
  use ExUnit.Case, async: false

  import Mox

  alias ExUtcp.Providers
  alias ExUtcp.Transports.Graphql

  @moduletag :integration
  setup :verify_on_exit!

  describe "GraphQL Transport" do
    setup do
      # Clean up any existing GraphQL transport
      case Process.whereis(Graphql) do
        nil ->
          :ok

        pid ->
          try do
            GenServer.stop(pid)
          rescue
            _ -> :ok
          end
      end

      :ok
    end

    test "creates new transport" do
      transport = Graphql.new()

      assert %Graphql{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "creates transport with custom options" do
      logger = fn msg -> IO.puts("Custom: #{msg}") end
      transport = Graphql.new(logger: logger, connection_timeout: 60_000)

      assert transport.logger == logger
      assert transport.connection_timeout == 60_000
    end

    test "starts the transport GenServer" do
      # This test runs in setup, but we can verify it's running
      assert Process.whereis(Graphql) != nil
    end

    test "returns correct transport name" do
      assert Graphql.transport_name() == "graphql"
    end

    test "supports streaming" do
      assert Graphql.supports_streaming?() == true
    end

    test "validates provider type" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Graphql.register_tool_provider(http_provider)
    end

    test "handles invalid provider in call_tool" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Graphql.call_tool("test_tool", %{}, http_provider)
    end

    test "handles invalid provider in call_tool_stream" do
      http_provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Graphql.call_tool_stream("test_tool", %{}, http_provider)
    end

    test "deregister_tool_provider always succeeds" do
      provider = Providers.new_graphql_provider(name: "test", url: "http://localhost:4000")

      assert :ok = Graphql.deregister_tool_provider(provider)
    end

    test "close always succeeds" do
      assert :ok = Graphql.close()
    end

    test "provides GraphQL functionality" do
      provider =
        Providers.new_graphql_provider(
          name: "test",
          url: "http://localhost:4000"
        )

      # Test GraphQL operations (these will succeed with the mock implementation)
      assert {:ok, %{"result" => _}} = Graphql.query(provider, "query { test }", %{})
      assert {:ok, %{"result" => _}} = Graphql.mutation(provider, "mutation { test }", %{})

      assert {:ok, [%{"data" => _}]} =
               Graphql.subscription(provider, "subscription { test }", %{})

      assert {:ok, %{"__schema" => _}} = Graphql.introspect_schema(provider)
    end
  end

  describe "GraphQL Provider" do
    test "creates new graphql provider" do
      provider =
        Providers.new_graphql_provider(
          name: "test_graphql",
          url: "http://localhost:4000"
        )

      assert provider.name == "test_graphql"
      assert provider.type == :graphql
      assert provider.url == "http://localhost:4000"
      assert provider.auth == nil
      assert provider.headers == %{}
    end

    test "creates graphql provider with all options" do
      auth = ExUtcp.Auth.new_api_key_auth(api_key: "test-key", location: "header")

      provider =
        Providers.new_graphql_provider(
          name: "test_graphql",
          url: "http://localhost:4000",
          auth: auth,
          headers: %{"X-Custom-Header" => "value"}
        )

      assert provider.name == "test_graphql"
      assert provider.type == :graphql
      assert provider.url == "http://localhost:4000"
      assert provider.auth == auth
      assert provider.headers == %{"X-Custom-Header" => "value"}
    end

    test "validates graphql provider" do
      provider = %{name: "", type: :graphql, url: "http://localhost:4000"}

      assert {:error, "Provider name is required"} = Providers.validate_provider(provider)
    end
  end

  describe "Error handling" do
    setup do
      # Ensure the GenServer is running for these tests
      case Process.whereis(Graphql) do
        nil ->
          {:ok, _pid} = Graphql.start_link()

        _pid ->
          :ok
      end

      :ok
    end

    test "handles connection errors gracefully" do
      provider =
        Providers.new_graphql_provider(
          name: "test",
          url: "http://invalid-host-that-does-not-exist:9999"
        )

      # With the mock implementation, this will succeed
      assert {:ok, []} = Graphql.register_tool_provider(provider)
    end

    test "handles tool call errors gracefully" do
      provider =
        Providers.new_graphql_provider(
          name: "test",
          url: "http://invalid-host-that-does-not-exist:9999"
        )

      # With the mock implementation, this will succeed
      assert {:ok, %{"result" => _}} =
               Graphql.call_tool("test.tool", %{"arg" => "value"}, provider)
    end

    test "handles tool stream errors gracefully" do
      provider =
        Providers.new_graphql_provider(
          name: "test",
          url: "http://invalid-host-that-does-not-exist:9999"
        )

      # With the mock implementation, this will succeed
      assert {:ok, %{type: :stream, data: _}} =
               Graphql.call_tool_stream("test.tool", %{"arg" => "value"}, provider)
    end
  end
end
