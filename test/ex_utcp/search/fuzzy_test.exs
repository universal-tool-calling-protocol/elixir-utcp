defmodule ExUtcp.Search.FuzzyTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Search.Fuzzy

  @moduletag :unit

  describe "String Similarity" do
    test "calculates exact match similarity" do
      assert Fuzzy.string_similarity("test", "test") == 1.0
    end

    test "calculates substring similarity" do
      similarity = Fuzzy.string_similarity("testing", "test")
      assert similarity == 0.8
    end

    test "calculates fuzzy similarity for similar strings" do
      similarity = Fuzzy.string_similarity("test", "tset")
      assert similarity >= 0.5
    end

    test "calculates low similarity for different strings" do
      similarity = Fuzzy.string_similarity("test", "completely different")
      assert similarity < 0.3
    end

    test "best_similarity works with FuzzyCompare" do
      similarity = Fuzzy.best_similarity("test", "tset")
      assert is_float(similarity)
      assert similarity >= 0.0 and similarity <= 1.0
      # Should be high for similar strings
      assert similarity > 0.5
    end

    test "levenshtein_distance calculates correctly" do
      distance = Fuzzy.levenshtein_distance("test", "tset")
      assert is_integer(distance)
      assert distance >= 0
    end

    test "levenshtein_similarity works" do
      similarity = Fuzzy.levenshtein_similarity("test", "tset")
      assert is_float(similarity)
      assert similarity >= 0.0 and similarity <= 1.0
    end
  end

  describe "Tool Search" do
    test "searches tools with fuzzy matching" do
      tools = [
        create_test_tool("get_user", "Get user information"),
        create_test_tool("create_user", "Create new user"),
        create_test_tool("list_files", "List directory files")
      ]

      results =
        Fuzzy.search_tools(tools, "get_usr", %{threshold: 0.5, include_descriptions: true})

      assert is_list(results)
      assert length(results) >= 1

      # Should find "get_user" with reasonable similarity
      get_user_result = Enum.find(results, &(&1.tool.name == "get_user"))
      assert get_user_result != nil
      assert get_user_result.score > 0.5
      assert get_user_result.match_type == :fuzzy
    end

    test "searches tools with description matching" do
      tools = [
        create_test_tool("tool1", "Process user data"),
        create_test_tool("tool2", "Handle file operations"),
        create_test_tool("tool3", "Manage user accounts")
      ]

      results = Fuzzy.search_tools(tools, "user", %{threshold: 0.3, include_descriptions: true})

      assert length(results) >= 2

      # Should find tools with "user" in description
      user_tools =
        Enum.filter(results, fn result ->
          String.contains?(result.tool.definition.description, "user")
        end)

      assert length(user_tools) >= 2
    end
  end

  describe "Provider Search" do
    test "searches providers with fuzzy matching" do
      providers = [
        %{name: "api_provider", type: :http},
        %{name: "websocket_provider", type: :websocket},
        %{name: "grpc_service", type: :grpc}
      ]

      results = Fuzzy.search_providers(providers, "api_provdr", %{threshold: 0.5})

      assert length(results) >= 1

      # Should find "api_provider" with reasonable similarity
      api_result = Enum.find(results, &(&1.provider.name == "api_provider"))
      assert api_result != nil
      assert api_result.score > 0.5
    end

    test "searches providers by type" do
      providers = [
        %{name: "http_api", type: :http},
        %{name: "ws_connection", type: :websocket},
        %{name: "grpc_service", type: :grpc}
      ]

      results = Fuzzy.search_providers(providers, "websocket", %{threshold: 0.3})

      assert length(results) >= 1

      # Should find WebSocket provider
      ws_result = Enum.find(results, &(&1.provider.type == :websocket))
      assert ws_result != nil
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
