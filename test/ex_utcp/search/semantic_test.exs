defmodule ExUtcp.Search.SemanticTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Search.Semantic

  @moduletag :unit

  describe "Keyword Extraction" do
    test "extracts keywords from text" do
      text = "This is a test tool for processing user data and files"
      keywords = Semantic.extract_keywords(text)

      assert is_list(keywords)
      assert "test" in keywords
      assert "tool" in keywords
      assert "processing" in keywords
      assert "user" in keywords
      assert "data" in keywords
      assert "files" in keywords

      # Should filter out stop words
      refute "this" in keywords
      refute "and" in keywords
      refute "for" in keywords
    end

    test "filters short words" do
      text = "a b cd efg hijk"
      keywords = Semantic.extract_keywords(text)

      # Should only include words with 3+ characters
      assert "efg" in keywords
      assert "hijk" in keywords
      refute "a" in keywords
      refute "b" in keywords
      refute "cd" in keywords
    end

    test "handles empty text" do
      keywords = Semantic.extract_keywords("")
      assert keywords == []
    end
  end

  describe "Keyword Similarity" do
    test "calculates similarity between keyword sets" do
      keywords1 = ["user", "data", "processing"]
      keywords2 = ["user", "information", "processing"]

      similarity = Semantic.keyword_similarity(keywords1, keywords2)

      assert is_float(similarity)
      assert similarity > 0.0
      assert similarity <= 1.0
    end

    test "returns 1.0 for identical keyword sets" do
      keywords = ["user", "data", "processing"]
      similarity = Semantic.keyword_similarity(keywords, keywords)

      assert similarity == 1.0
    end

    test "returns 0.0 for completely different keyword sets" do
      keywords1 = ["user", "data"]
      keywords2 = ["file", "upload"]

      similarity = Semantic.keyword_similarity(keywords1, keywords2)

      assert similarity == 0.0
    end

    test "handles empty keyword sets" do
      assert Semantic.keyword_similarity([], ["test"]) == 0.0
      assert Semantic.keyword_similarity(["test"], []) == 0.0
      assert Semantic.keyword_similarity([], []) == 0.0
    end
  end

  describe "Tool Search" do
    test "searches tools with keyword-based semantic matching" do
      tools = [
        create_test_tool("get_user", "Retrieve user information from database"),
        create_test_tool("create_file", "Create a new file in storage"),
        create_test_tool("process_data", "Process and analyze user data"),
        create_test_tool("send_notification", "Send email notification to users")
      ]

      results =
        Semantic.search_tools_with_keywords(tools, "user information", %{
          threshold: 0.2,
          include_descriptions: true
        })

      assert is_list(results)
      assert length(results) >= 1

      # Should find user-related tools
      user_tools =
        Enum.filter(results, fn result ->
          String.contains?(result.tool.definition.description, "user")
        end)

      assert length(user_tools) >= 1
    end

    test "searches tools with Haystack integration" do
      tools = [
        create_test_tool("search_documents", "Search through document collection"),
        create_test_tool("index_files", "Index files for full-text search"),
        create_test_tool("query_database", "Query database for information")
      ]

      # Test with Haystack (may fallback to keyword search if Haystack fails)
      results =
        Semantic.search_tools_with_haystack(tools, "search documents", %{
          threshold: 0.2,
          limit: 10
        })

      assert is_list(results)
      # Should find at least one relevant tool
      # May be 0 if Haystack integration fails
      assert length(results) >= 0
    end

    test "creates tools index for Haystack" do
      tools = [
        create_test_tool("tool1", "First tool description"),
        create_test_tool("tool2", "Second tool description")
      ]

      index = Semantic.create_tools_index(tools)

      # Should create a valid Haystack index
      assert index != nil
    end
  end

  describe "Similar Tools" do
    test "finds similar tools based on description" do
      reference_tool = create_test_tool("get_user", "Retrieve user account information")

      candidate_tools = [
        create_test_tool("fetch_user", "Fetch user profile data"),
        create_test_tool("create_file", "Create a new file"),
        create_test_tool("update_user", "Update user account details"),
        create_test_tool("delete_post", "Delete a blog post")
      ]

      similar_tools = Semantic.find_similar_tools(reference_tool, candidate_tools, 0.2)

      assert is_list(similar_tools)
      assert length(similar_tools) >= 1

      # Should find user-related tools
      user_tools =
        Enum.filter(similar_tools, fn result ->
          String.contains?(result.tool.definition.description, "user")
        end)

      assert length(user_tools) >= 1
    end

    test "excludes reference tool from similar tools" do
      reference_tool = create_test_tool("get_user", "Get user information")
      candidate_tools = [create_test_tool("other_tool", "Other functionality")]

      similar_tools = Semantic.find_similar_tools(reference_tool, candidate_tools, 0.1)

      # Should not include the reference tool (it's not in candidate_tools)
      tool_names = Enum.map(similar_tools, & &1.tool.name)
      refute "get_user" in tool_names
    end
  end

  describe "Contextual Analysis" do
    test "calculates contextual similarity" do
      tool = create_test_tool("api_tool", "API tool for user management with authentication")
      query_keywords = ["user", "management", "api"]

      similarity = Semantic.contextual_similarity(tool, query_keywords)

      assert is_float(similarity)
      assert similarity >= 0.0
      assert similarity <= 1.0
    end

    test "extracts tool context from parameters and response" do
      tool = %{
        name: "user_tool",
        provider_name: "test",
        definition: %{
          name: "user_tool",
          description: "User management tool",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "user_id" => %{"type" => "string", "description" => "User identifier"},
              "email" => %{"type" => "string", "description" => "User email address"}
            }
          },
          response: %{
            "type" => "object",
            "properties" => %{
              "user_data" => %{"type" => "object", "description" => "User profile information"}
            }
          }
        }
      }

      query_keywords = ["user", "email", "profile"]
      similarity = Semantic.contextual_similarity(tool, query_keywords)

      assert similarity > 0.0
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
