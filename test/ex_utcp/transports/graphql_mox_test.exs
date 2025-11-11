defmodule ExUtcp.Transports.GraphqlMoxTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExUtcp.Transports.Graphql.Testable

  @moduletag :unit

  # Mocks are defined in test_helper.exs

  setup :verify_on_exit!

  describe "GraphQL Transport with Mocks" do
    setup do
      # Create testable transport with mocked dependencies
      transport =
        Testable.new(
          connection_module: ExUtcp.Transports.Graphql.ConnectionMock,
          pool_module: ExUtcp.Transports.Graphql.PoolMock
        )

      {:ok, transport: transport}
    end

    test "creates new transport", %{transport: transport} do
      assert %Testable{} = transport
      assert transport.logger != nil
      assert transport.connection_timeout == 30_000
    end

    test "returns correct transport name" do
      assert Testable.transport_name() == "graphql"
    end

    test "supports streaming" do
      assert Testable.supports_streaming?() == true
    end

    test "validates provider type" do
      valid_provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      invalid_provider = %{
        name: "test",
        type: :http,
        url: "http://localhost:4000",
        auth: nil,
        headers: %{}
      }

      # Test with valid provider - this will succeed with mocks
      assert {:ok, _tools} = Testable.register_tool_provider(valid_provider)

      # Test with invalid provider type
      assert {:error, "GraphQL transport can only be used with GraphQL providers"} =
               Testable.register_tool_provider(invalid_provider)
    end

    test "registers tool provider successfully", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return successful tool discovery
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :introspect_schema, fn _conn, _opts ->
        {:ok, %{"__schema" => %{"types" => []}}}
      end)

      assert {:ok, []} = Testable.register_tool_provider(transport, provider)
    end

    test "handles provider registration errors", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return an error during tool discovery
      # (expect 4 calls due to retry logic: 1 initial + 3 retries)
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :introspect_schema, 4, fn _conn, _opts ->
        {:error, "Schema introspection failed"}
      end)

      assert {:error, _reason} = Testable.register_tool_provider(transport, provider)
    end

    test "deregisters tool provider", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      assert :ok = Testable.deregister_tool_provider(transport, provider)
    end

    test "executes query successfully", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return a successful query result
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :query, fn _conn,
                                                                  _query,
                                                                  _variables,
                                                                  _opts ->
        {:ok, %{"data" => %{"test_tool" => %{"result" => "success"}}}}
      end)

      assert {:ok, result} = Testable.call_tool(transport, "test_tool", %{}, provider)
      assert %{"data" => %{"test_tool" => %{"result" => "success"}}} = result
    end

    test "handles query errors", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # The Testable module returns mock_connection directly without using the pool
      # Mock the connection to return an error (expect 4 calls due to retry logic: 1 initial + 3 retries)
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :query, 4, fn _conn,
                                                                     _query,
                                                                     _vars,
                                                                     _opts ->
        {:error, "Query failed"}
      end)

      assert {:error, _reason} = Testable.call_tool(transport, "test_tool", %{}, provider)
    end

    test "executes mutation successfully", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return query result
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :query, fn _conn, _query, _vars, _opts ->
        {:ok, %{"data" => %{"create" => %{"id" => "123"}}}}
      end)

      assert {:ok, %{"data" => %{"create" => %{"id" => "123"}}}} =
               Testable.call_tool(transport, "create_tool", %{"name" => "test"}, provider)
    end

    test "executes subscription successfully", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return a successful subscription result
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :subscription, fn _conn,
                                                                         _query,
                                                                         _variables,
                                                                         _opts ->
        {:ok,
         [%{"data" => %{"subscribe_tool" => %{"data" => "test", "timestamp" => "2024-01-01"}}}]}
      end)

      assert {:ok, result} = Testable.call_tool_stream(transport, "subscribe_tool", %{}, provider)

      assert %{
               type: :stream,
               data: [
                 %{
                   "data" => %{
                     "subscribe_tool" => %{"data" => "test", "timestamp" => "2024-01-01"}
                   }
                 }
               ]
             } = result
    end

    test "handles connection errors gracefully", %{transport: transport} do
      provider = %{
        name: "test",
        type: :graphql,
        url: "http://localhost:4000/graphql",
        auth: nil,
        headers: %{}
      }

      # Mock the connection to return an error (expect 4 calls due to retry logic: 1 initial + 3 retries)
      expect(ExUtcp.Transports.Graphql.ConnectionMock, :query, 4, fn _conn,
                                                                     _query,
                                                                     _variables,
                                                                     _opts ->
        {:error, "Connection failed"}
      end)

      assert {:error, _reason} = Testable.call_tool(transport, "test_tool", %{}, provider)
    end

    test "closes transport successfully", %{transport: transport} do
      assert :ok = Testable.close(transport)
    end
  end
end
