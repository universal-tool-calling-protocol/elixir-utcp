defmodule ExUtcp.OpenApiConverter.GeneratorTest do
  use ExUnit.Case, async: true

  alias ExUtcp.OpenApiConverter.Generator
  alias ExUtcp.OpenApiConverter.Types, as: T

  describe "generate_tools/2" do
    test "generates tools from parsed spec" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{
          title: "Test API",
          description: "A test API",
          version: "1.0.0"
        },
        servers: [
          %T.ParsedServer{url: "https://api.example.com/v1"}
        ],
        paths: [
          %T.ParsedPath{
            path: "/users",
            operations: [
              %T.ParsedOperation{
                method: "get",
                path: "/users",
                operation_id: "getUsers",
                summary: "Get users",
                description: "Retrieve a list of users",
                tags: ["users"],
                parameters: [
                  %T.ParsedParameter{
                    name: "limit",
                    in: "query",
                    description: "Number of users to return",
                    required: false,
                    schema: %T.OpenApiSchema{type: "integer"},
                    style: nil,
                    explode: nil,
                    example: 10
                  }
                ],
                request_body: nil,
                responses: [
                  %T.ParsedResponse{
                    status_code: "200",
                    description: "Successful response",
                    content_types: ["application/json"],
                    schema: %T.OpenApiSchema{
                      type: "array",
                      items: %T.OpenApiSchema{
                        type: "object",
                        properties: %{
                          "id" => %T.OpenApiSchema{type: "integer"},
                          "name" => %T.OpenApiSchema{type: "string"}
                        }
                      }
                    }
                  }
                ],
                security: [],
                deprecated: false
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec)

      assert length(tools) == 1

      tool = List.first(tools)
      assert tool.name == "getUsers"
      assert tool.description == "Get users - Retrieve a list of users"
      assert tool.provider.type == :http
      assert tool.provider.http_method == "GET"
      assert tool.provider.url == "https://api.example.com/v1/users"
    end

    test "applies conversion options" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [
          %T.ParsedPath{
            path: "/users",
            operations: [
              %T.ParsedOperation{
                method: "get",
                path: "/users",
                operation_id: "getUsers",
                summary: "Get users",
                description: nil,
                tags: [],
                parameters: [],
                request_body: nil,
                responses: [],
                security: [],
                deprecated: false
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      opts = [
        prefix: "test",
        base_url: "https://custom.api.com",
        auth: %{
          type: :api_key,
          api_key: "Bearer ${TOKEN}",
          location: :header,
          var_name: "Authorization"
        }
      ]

      {:ok, tools} = Generator.generate_tools(parsed_spec, opts)

      tool = List.first(tools)
      assert tool.name == "test.getUsers"
      assert tool.provider.url == "https://custom.api.com/users"
      assert tool.provider.auth.api_key == "Bearer ${TOKEN}"
    end

    test "filters deprecated operations" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [
          %T.ParsedPath{
            path: "/users",
            operations: [
              %T.ParsedOperation{
                method: "get",
                path: "/users",
                operation_id: "getUsers",
                summary: "Get users",
                description: nil,
                tags: [],
                parameters: [],
                request_body: nil,
                responses: [],
                security: [],
                deprecated: true
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec, include_deprecated: false)
      assert Enum.empty?(tools)

      {:ok, tools} = Generator.generate_tools(parsed_spec, include_deprecated: true)
      assert length(tools) == 1
    end

    test "handles request body parameters" do
      parsed_spec = %T.ParsedSpec{
        version: "3.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [
          %T.ParsedPath{
            path: "/users",
            operations: [
              %T.ParsedOperation{
                method: "post",
                path: "/users",
                operation_id: "createUser",
                summary: "Create user",
                description: nil,
                tags: [],
                parameters: [],
                request_body: %T.ParsedRequestBody{
                  description: "User data",
                  required: true,
                  content_types: ["application/json"],
                  schema: %T.OpenApiSchema{
                    type: "object",
                    properties: %{
                      "name" => %T.OpenApiSchema{type: "string"},
                      "email" => %T.OpenApiSchema{type: "string"}
                    },
                    required: ["name", "email"]
                  }
                },
                responses: [],
                security: [],
                deprecated: false
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec)

      tool = List.first(tools)
      assert tool.name == "createUser"
      assert tool.provider.http_method == "POST"

      # Check input schema includes request body
      input_schema = tool.input_schema
      assert Map.has_key?(input_schema["properties"], "body")
      assert "body" in input_schema["required"]
    end

    test "handles path parameters" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [
          %T.ParsedPath{
            path: "/users/{id}",
            operations: [
              %T.ParsedOperation{
                method: "get",
                path: "/users/{id}",
                operation_id: "getUser",
                summary: "Get user",
                description: nil,
                tags: [],
                parameters: [
                  %T.ParsedParameter{
                    name: "id",
                    in: "path",
                    description: "User ID",
                    required: true,
                    schema: %T.OpenApiSchema{type: "integer"},
                    style: nil,
                    explode: nil,
                    example: 123
                  }
                ],
                request_body: nil,
                responses: [],
                security: [],
                deprecated: false
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec)

      tool = List.first(tools)
      assert tool.name == "getUser"
      assert tool.provider.url == "https://api.example.com/v1/users/{id}"

      # Check input schema includes path parameter
      input_schema = tool.input_schema
      assert Map.has_key?(input_schema["properties"], "id")
      assert "id" in input_schema["required"]
    end

    test "handles query parameters" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [
          %T.ParsedPath{
            path: "/users",
            operations: [
              %T.ParsedOperation{
                method: "get",
                path: "/users",
                operation_id: "getUsers",
                summary: "Get users",
                description: nil,
                tags: [],
                parameters: [
                  %T.ParsedParameter{
                    name: "limit",
                    in: "query",
                    description: "Number of users to return",
                    required: false,
                    schema: %T.OpenApiSchema{type: "integer"},
                    style: nil,
                    explode: nil,
                    example: 10
                  },
                  %T.ParsedParameter{
                    name: "offset",
                    in: "query",
                    description: "Number of users to skip",
                    required: true,
                    schema: %T.OpenApiSchema{type: "integer"},
                    style: nil,
                    explode: nil,
                    example: 0
                  }
                ],
                request_body: nil,
                responses: [],
                security: [],
                deprecated: false
              }
            ]
          }
        ],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec)

      tool = List.first(tools)

      # Check input schema includes query parameters
      input_schema = tool.input_schema
      assert Map.has_key?(input_schema["properties"], "limit")
      assert Map.has_key?(input_schema["properties"], "offset")
      assert "offset" in input_schema["required"]
      refute "limit" in input_schema["required"]
    end

    test "handles error cases" do
      parsed_spec = %T.ParsedSpec{
        version: "2.0",
        info: %T.ParsedInfo{title: "Test API", version: "1.0.0"},
        servers: [%T.ParsedServer{url: "https://api.example.com/v1"}],
        paths: [],
        components: %{security_schemes: %{}},
        security: [],
        tags: [],
        external_docs: nil
      }

      {:ok, tools} = Generator.generate_tools(parsed_spec)
      assert Enum.empty?(tools)
    end
  end
end
