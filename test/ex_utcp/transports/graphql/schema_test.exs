defmodule ExUtcp.Transports.Graphql.SchemaTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Transports.Graphql.Schema

  describe "GraphQL Schema Utilities" do
    test "extracts tools from schema" do
      schema = %{
        "__schema" => %{
          "queryType" => %{"name" => "Query"},
          "mutationType" => %{"name" => "Mutation"},
          "subscriptionType" => %{"name" => "Subscription"},
          "types" => [
            %{
              "name" => "Query",
              "fields" => [
                %{
                  "name" => "getUser",
                  "description" => "Get user by ID",
                  "args" => [
                    %{
                      "name" => "id",
                      "description" => "User ID",
                      "type" => %{
                        "kind" => "NON_NULL",
                        "ofType" => %{"kind" => "SCALAR", "name" => "String"}
                      }
                    }
                  ]
                }
              ]
            },
            %{
              "name" => "Mutation",
              "fields" => [
                %{
                  "name" => "createUser",
                  "description" => "Create a new user",
                  "args" => [
                    %{
                      "name" => "input",
                      "description" => "User input",
                      "type" => %{
                        "kind" => "NON_NULL",
                        "ofType" => %{"kind" => "SCALAR", "name" => "String"}
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
      }

      tools = Schema.extract_tools(schema)

      assert length(tools) == 2
      assert Enum.any?(tools, fn tool -> tool["name"] == "getUser" end)
      assert Enum.any?(tools, fn tool -> tool["name"] == "createUser" end)
    end

    test "validates query string" do
      assert {:ok, "query { test }"} = Schema.validate_query("query { test }")
      assert {:ok, "mutation { test }"} = Schema.validate_query("mutation { test }")
      assert {:ok, "subscription { test }"} = Schema.validate_query("subscription { test }")
    end

    test "rejects invalid query string" do
      assert {:error, "Empty query"} = Schema.validate_query("")

      assert {:error, "Query must contain query, mutation, or subscription"} =
               Schema.validate_query("invalid")

      assert {:error, "Query must contain selection set"} = Schema.validate_query("query")
    end

    test "builds query from tool name and arguments" do
      query = Schema.build_query("user.get", %{"id" => "123"})

      assert String.contains?(query, "query user_get")
      assert String.contains?(query, "user_get($id: String)")
    end

    test "builds mutation from tool name and arguments" do
      mutation = Schema.build_mutation("user.create", %{"name" => "John"})

      assert String.contains?(mutation, "mutation user_create")
      assert String.contains?(mutation, "user_create($name: String)")
    end

    test "builds subscription from tool name and arguments" do
      subscription = Schema.build_subscription("user.subscribe", %{"id" => "123"})

      assert String.contains?(subscription, "subscription user_subscribe")
      assert String.contains?(subscription, "user_subscribe($id: String)")
    end

    test "parses GraphQL response" do
      response = %{"data" => %{"result" => "success"}, "errors" => nil}
      assert {:ok, %{"result" => "success"}} = Schema.parse_response(response)
    end

    test "handles GraphQL response with errors" do
      response = %{"data" => %{"result" => "success"}, "errors" => ["Some error"]}
      assert {:ok, %{"result" => "success"}} = Schema.parse_response(response)
    end

    test "handles GraphQL response with only errors" do
      response = %{"errors" => ["Some error"]}
      assert {:error, "GraphQL errors: [\"Some error\"]"} = Schema.parse_response(response)
    end

    test "handles invalid response format" do
      response = %{"invalid" => "format"}
      assert {:error, "Invalid GraphQL response format"} = Schema.parse_response(response)
    end
  end
end
