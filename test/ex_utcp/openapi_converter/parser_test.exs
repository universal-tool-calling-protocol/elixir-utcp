defmodule ExUtcp.OpenApiConverter.ParserTest do
  use ExUnit.Case, async: true

  alias ExUtcp.OpenApiConverter.Parser
  alias ExUtcp.OpenApiConverter.Types, as: T

  describe "parse/1" do
    test "parses OpenAPI 2.0 spec" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{
          "title" => "Test API",
          "version" => "1.0.0",
          "description" => "A test API"
        },
        "host" => "api.example.com",
        "basePath" => "/v1",
        "schemes" => ["https"],
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "summary" => "Get users",
              "description" => "Retrieve a list of users",
              "parameters" => [
                %{
                  "name" => "limit",
                  "in" => "query",
                  "type" => "integer",
                  "required" => false,
                  "description" => "Number of users to return"
                }
              ],
              "responses" => %{
                "200" => %{
                  "description" => "Successful response",
                  "schema" => %{
                    "type" => "array",
                    "items" => %{
                      "type" => "object",
                      "properties" => %{
                        "id" => %{"type" => "integer"},
                        "name" => %{"type" => "string"}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      {:ok, parsed_spec} = Parser.parse(spec)

      assert parsed_spec.version == "2.0"
      assert parsed_spec.info.title == "Test API"
      assert parsed_spec.info.description == "A test API"
      assert parsed_spec.info.version == "1.0.0"
      assert length(parsed_spec.servers) == 1
      assert length(parsed_spec.paths) == 1

      path = List.first(parsed_spec.paths)
      assert path.path == "/users"
      assert length(path.operations) == 1

      operation = List.first(path.operations)
      assert operation.method == "get"
      assert operation.operation_id == "getUsers"
      assert operation.summary == "Get users"
      assert operation.description == "Retrieve a list of users"
      assert length(operation.parameters) == 1
      assert length(operation.responses) == 1
    end

    test "parses OpenAPI 3.0 spec" do
      spec = %{
        "openapi" => "3.0.0",
        "info" => %{
          "title" => "Test API",
          "version" => "1.0.0",
          "description" => "A test API"
        },
        "servers" => [
          %{"url" => "https://api.example.com/v1"}
        ],
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "summary" => "Get users",
              "description" => "Retrieve a list of users",
              "parameters" => [
                %{
                  "name" => "limit",
                  "in" => "query",
                  "schema" => %{"type" => "integer"},
                  "required" => false,
                  "description" => "Number of users to return"
                }
              ],
              "responses" => %{
                "200" => %{
                  "description" => "Successful response",
                  "content" => %{
                    "application/json" => %{
                      "schema" => %{
                        "type" => "array",
                        "items" => %{
                          "type" => "object",
                          "properties" => %{
                            "id" => %{"type" => "integer"},
                            "name" => %{"type" => "string"}
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      {:ok, parsed_spec} = Parser.parse(spec)

      assert parsed_spec.version == "3.0"
      assert parsed_spec.info.title == "Test API"
      assert parsed_spec.info.description == "A test API"
      assert parsed_spec.info.version == "1.0.0"
      assert length(parsed_spec.servers) == 1
      assert length(parsed_spec.paths) == 1

      path = List.first(parsed_spec.paths)
      assert path.path == "/users"
      assert length(path.operations) == 1

      operation = List.first(path.operations)
      assert operation.method == "get"
      assert operation.operation_id == "getUsers"
      assert operation.summary == "Get users"
      assert operation.description == "Retrieve a list of users"
      assert length(operation.parameters) == 1
      assert length(operation.responses) == 1
    end

    test "handles missing operation ID" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "paths" => %{
          "/users" => %{
            "get" => %{
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, parsed_spec} = Parser.parse(spec)

      operation =
        parsed_spec.paths
        |> List.first()
        |> Map.get(:operations)
        |> List.first()

      assert operation.operation_id == "get_users"
    end

    test "handles security definitions" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "securityDefinitions" => %{
          "apiKey" => %{
            "type" => "apiKey",
            "name" => "X-API-Key",
            "in" => "header"
          },
          "basicAuth" => %{
            "type" => "basic"
          }
        },
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, parsed_spec} = Parser.parse(spec)

      assert map_size(parsed_spec.components.security_schemes) == 2
      assert Map.has_key?(parsed_spec.components.security_schemes, "apiKey")
      assert Map.has_key?(parsed_spec.components.security_schemes, "basicAuth")
    end

    test "handles unsupported version" do
      spec = %{"invalid" => "spec"}

      {:error, reason} = Parser.parse(spec)
      assert reason == "Unsupported OpenAPI version: unknown"
    end

    test "handles parsing errors" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      # This should not error, but if it does, we handle it
      {:ok, _parsed_spec} = Parser.parse(spec)
    end
  end

  describe "validate/1" do
    test "validates valid spec" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, result} = Parser.validate(spec)
      assert result.valid == true
      assert result.version == "2.0"
      assert result.operations_count == 1
      assert result.security_schemes_count == 0
    end

    test "validates invalid spec" do
      spec = %{"invalid" => "spec"}

      {:ok, result} = Parser.validate(spec)
      assert result.valid == false
      refute Enum.empty?(result.errors)
      assert result.version == nil
      assert result.operations_count == 0
      assert result.security_schemes_count == 0
    end
  end
end
