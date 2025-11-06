defmodule ExUtcp.SearchTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Providers
  alias ExUtcp.Search
  alias ExUtcp.Search.Engine

  @moduletag :unit

  describe "Search Engine" do
    test "creates new search engine" do
      engine = Search.new()
      assert %Engine{} = engine
      assert engine.tools_index == %{}
      assert engine.providers_index == %{}
    end

    test "adds and retrieves tools" do
      engine = Search.new()

      tool = create_test_tool("test_tool", "A test tool for testing")
      engine = Engine.add_tool(engine, tool)

      assert Engine.get_tool(engine, "test_tool") == tool
      assert length(Engine.get_all_tools(engine)) == 1
    end

    test "adds and retrieves providers" do
      engine = Search.new()

      provider =
        Providers.new_http_provider(
          name: "test_provider",
          url: "https://api.example.com",
          http_method: "POST"
        )

      engine = Engine.add_provider(engine, provider)

      assert Engine.get_provider(engine, "test_provider") == provider
      assert length(Engine.get_all_providers(engine)) == 1
    end

    test "removes tools and providers" do
      engine = Search.new()

      tool = create_test_tool("test_tool", "A test tool")

      provider =
        Providers.new_http_provider(
          name: "test_provider",
          url: "https://api.example.com",
          http_method: "POST"
        )

      engine =
        engine
        |> Engine.add_tool(tool)
        |> Engine.add_provider(provider)

      assert length(Engine.get_all_tools(engine)) == 1
      assert length(Engine.get_all_providers(engine)) == 1

      engine =
        engine
        |> Engine.remove_tool("test_tool")
        |> Engine.remove_provider("test_provider")

      assert Enum.empty?(Engine.get_all_tools(engine))
      assert Enum.empty?(Engine.get_all_providers(engine))
    end

    test "clears all data" do
      engine = Search.new()

      tool = create_test_tool("test_tool", "A test tool")

      provider =
        Providers.new_http_provider(
          name: "test_provider",
          url: "https://api.example.com",
          http_method: "POST"
        )

      engine =
        engine
        |> Engine.add_tool(tool)
        |> Engine.add_provider(provider)

      engine = Engine.clear(engine)

      assert Enum.empty?(Engine.get_all_tools(engine))
      assert Enum.empty?(Engine.get_all_providers(engine))
    end

    test "provides statistics" do
      engine = Search.new()

      tool = create_test_tool("test_tool", "A test tool")

      provider =
        Providers.new_http_provider(
          name: "test_provider",
          url: "https://api.example.com",
          http_method: "POST"
        )

      engine =
        engine
        |> Engine.add_tool(tool)
        |> Engine.add_provider(provider)

      stats = Engine.stats(engine)

      assert stats.tools_count == 1
      assert stats.providers_count == 1
      assert is_map(stats.config)
    end
  end

  describe "Tool Search" do
    setup do
      engine = Search.new()

      tools = [
        create_test_tool("get_user", "Get user information from the database"),
        create_test_tool("create_user", "Create a new user account"),
        create_test_tool("update_user", "Update existing user information"),
        create_test_tool("delete_user", "Delete a user account"),
        create_test_tool("list_files", "List files in a directory"),
        create_test_tool("upload_file", "Upload a file to storage"),
        create_test_tool("send_email", "Send an email notification"),
        create_test_tool("process_payment", "Process a payment transaction")
      ]

      engine = Enum.reduce(tools, engine, &Engine.add_tool(&2, &1))

      %{engine: engine, tools: tools}
    end

    test "exact search finds exact matches", %{engine: engine} do
      results = Search.search_tools(engine, "get_user", %{algorithm: :exact})

      assert length(results) == 1
      assert hd(results).tool.name == "get_user"
      assert hd(results).match_type == :exact
      # May be boosted by ranking algorithm
      assert hd(results).score >= 1.0
    end

    test "fuzzy search finds approximate matches", %{engine: engine} do
      results = Search.search_tools(engine, "get_usr", %{algorithm: :fuzzy, threshold: 0.5})

      assert length(results) >= 1

      # Should find "get_user" with high similarity
      get_user_result = Enum.find(results, &(&1.tool.name == "get_user"))
      assert get_user_result != nil
      assert get_user_result.match_type == :fuzzy
      assert get_user_result.score > 0.5
    end

    test "semantic search finds related tools", %{engine: engine} do
      results =
        Search.search_tools(engine, "user management", %{
          algorithm: :semantic,
          # Lower threshold for testing
          threshold: 0.1,
          # Use keyword-based for testing
          use_haystack: false
        })

      # At least one result
      assert length(results) >= 1

      # Should find user-related tools
      user_tools = Enum.filter(results, &String.contains?(&1.tool.name, "user"))
      # At least one user tool
      assert length(user_tools) >= 1
    end

    test "combined search provides comprehensive results", %{engine: engine} do
      results = Search.search_tools(engine, "user", %{algorithm: :combined, threshold: 0.1})

      assert length(results) >= 3

      # Should include exact, fuzzy, and semantic matches
      match_types = Enum.map(results, & &1.match_type) |> Enum.uniq()
      assert :exact in match_types or :fuzzy in match_types or :semantic in match_types
    end

    test "search with filters", %{engine: engine} do
      # Add providers to test filtering
      provider1 =
        Providers.new_http_provider(
          name: "api_provider",
          url: "https://api.example.com",
          http_method: "GET"
        )

      provider2 = Providers.new_cli_provider(name: "cli_provider", command_name: "test")

      engine =
        engine
        |> Engine.add_provider(provider1)
        |> Engine.add_provider(provider2)

      # Test provider filtering
      results =
        Search.search_tools(engine, "user", %{
          algorithm: :combined,
          filters: %{providers: ["api_provider"]},
          threshold: 0.1
        })

      # All results should be from the specified provider
      Enum.each(results, fn result ->
        assert result.tool.provider_name == "api_provider"
      end)
    end

    test "search with security scanning", %{engine: engine} do
      # Create a tool with potential sensitive data
      sensitive_tool = create_test_tool("api_tool", "API tool with key: sk-1234567890abcdef")
      engine = Engine.add_tool(engine, sensitive_tool)

      results =
        Search.search_tools(engine, "api", %{
          algorithm: :exact,
          security_scan: true
        })

      assert length(results) >= 1

      # Check that security warnings are included
      api_result = Enum.find(results, &(&1.tool.name == "api_tool"))
      assert api_result != nil
      assert Map.has_key?(api_result, :security_warnings)
    end

    test "search with sensitive data filtering", %{engine: engine} do
      # Create tools with and without sensitive data
      normal_tool = create_test_tool("normal_tool", "A normal tool")
      sensitive_tool = create_test_tool("sensitive_tool", "Tool with password: secret123")

      engine =
        engine
        |> Engine.add_tool(normal_tool)
        |> Engine.add_tool(sensitive_tool)

      results =
        Search.search_tools(engine, "tool", %{
          algorithm: :fuzzy,
          security_scan: true,
          filter_sensitive: true,
          threshold: 0.3
        })

      # Sensitive tool should be filtered out
      tool_names = Enum.map(results, & &1.tool.name)
      assert "normal_tool" in tool_names
      refute "sensitive_tool" in tool_names
    end

    test "search suggestions", %{engine: engine} do
      suggestions = Search.get_suggestions(engine, "us", limit: 5)

      assert is_list(suggestions)
      assert length(suggestions) <= 5

      # Should include user-related suggestions
      user_suggestions = Enum.filter(suggestions, &String.contains?(&1, "user"))
      refute Enum.empty?(user_suggestions)
    end

    test "similar tools discovery", %{engine: engine} do
      reference_tool = create_test_tool("get_user", "Get user information from the database")
      engine = Engine.add_tool(engine, reference_tool)

      similar_tools = Search.suggest_similar_tools(engine, reference_tool, limit: 3)

      assert is_list(similar_tools)
      assert length(similar_tools) <= 3

      # Should not include the reference tool itself
      tool_names = Enum.map(similar_tools, & &1.tool.name)
      refute "get_user" in tool_names
    end
  end

  describe "Provider Search" do
    setup do
      engine = Search.new()

      providers = [
        Providers.new_http_provider(
          name: "api_provider",
          url: "https://api.example.com",
          http_method: "GET"
        ),
        Providers.new_websocket_provider(name: "ws_provider", url: "wss://ws.example.com"),
        Providers.new_grpc_provider(
          name: "grpc_provider",
          url: "grpc://grpc.example.com",
          proto_path: "/path",
          service_name: "Service"
        ),
        Providers.new_cli_provider(name: "cli_provider", command_name: "test")
      ]

      engine = Enum.reduce(providers, engine, &Engine.add_provider(&2, &1))

      %{engine: engine, providers: providers}
    end

    test "searches providers by name", %{engine: engine} do
      results = Search.search_providers(engine, "api_provider", %{algorithm: :exact})

      assert length(results) == 1
      assert hd(results).provider.name == "api_provider"
    end

    test "searches providers by type", %{engine: engine} do
      results = Search.search_providers(engine, "http", %{algorithm: :fuzzy, threshold: 0.5})

      assert length(results) >= 1

      # Should find HTTP provider
      http_result = Enum.find(results, &(&1.provider.type == :http))
      assert http_result != nil
    end

    test "filters providers by transport", %{engine: engine} do
      results =
        Search.search_providers(engine, "provider", %{
          algorithm: :fuzzy,
          filters: %{transports: [:websocket, :grpc]},
          threshold: 0.3
        })

      # Should only return WebSocket and gRPC providers
      transport_types = Enum.map(results, & &1.provider.type) |> Enum.uniq()
      assert Enum.all?(transport_types, &(&1 in [:websocket, :grpc]))
    end
  end

  # Helper functions

  defp create_test_tool(name, description, provider_name \\ "test_provider") do
    %{
      name: name,
      provider_name: provider_name,
      definition: %{
        name: name,
        description: description,
        parameters: %{
          "type" => "object",
          "properties" => %{
            "input" => %{
              "type" => "string",
              "description" => "Input parameter"
            }
          }
        },
        response: %{
          "type" => "object",
          "properties" => %{
            "result" => %{
              "type" => "string",
              "description" => "Operation result"
            }
          }
        }
      }
    }
  end
end
