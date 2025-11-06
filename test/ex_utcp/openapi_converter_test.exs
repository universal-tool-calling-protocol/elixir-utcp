defmodule ExUtcp.OpenApiConverterTest do
  use ExUnit.Case, async: true

  alias ExUtcp.OpenApiConverter

  describe "convert/2" do
    test "converts OpenAPI 2.0 spec to UTCP manual" do
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

      {:ok, manual} = OpenApiConverter.convert(spec)

      assert manual.name == "Test API"
      assert manual.description == "A test API"
      assert length(manual.tools) == 1

      tool = List.first(manual.tools)
      assert tool.name == "getUsers"
      assert tool.description == "Get users - Retrieve a list of users"
      assert tool.provider.type == :http
      assert tool.provider.http_method == "GET"
      assert tool.provider.url == "https://api.example.com/v1/users"
    end

    test "converts OpenAPI 3.0 spec to UTCP manual" do
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

      {:ok, manual} = OpenApiConverter.convert(spec)

      assert manual.name == "Test API"
      assert manual.description == "A test API"
      assert length(manual.tools) == 1

      tool = List.first(manual.tools)
      assert tool.name == "getUsers"
      assert tool.description == "Get users - Retrieve a list of users"
      assert tool.provider.type == :http
      assert tool.provider.http_method == "GET"
      assert tool.provider.url == "https://api.example.com/v1/users"
    end

    test "handles authentication schemes" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "securityDefinitions" => %{
          "apiKey" => %{
            "type" => "apiKey",
            "name" => "X-API-Key",
            "in" => "header"
          }
        },
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "security" => [%{"apiKey" => []}],
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, manual} = OpenApiConverter.convert(spec)

      tool = List.first(manual.tools)
      assert tool.provider.auth.type == :api_key
      assert tool.provider.auth.var_name == "X-API-Key"
      assert tool.provider.auth.location == :header
    end

    test "applies conversion options" do
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

      {:ok, manual} = OpenApiConverter.convert(spec, opts)

      tool = List.first(manual.tools)
      assert tool.name == "test.getUsers"
      assert tool.provider.url == "https://custom.api.com/users"
      assert tool.provider.auth.api_key == "Bearer ${TOKEN}"
    end

    test "filters deprecated operations" do
      spec = %{
        "swagger" => "2.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "host" => "api.example.com",
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "deprecated" => true,
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, manual} = OpenApiConverter.convert(spec, include_deprecated: false)
      assert Enum.empty?(manual.tools)

      {:ok, manual} = OpenApiConverter.convert(spec, include_deprecated: true)
      assert length(manual.tools) == 1
    end

    test "handles invalid spec" do
      spec = %{"invalid" => "spec"}

      {:error, reason} = OpenApiConverter.convert(spec)
      assert is_binary(reason)
    end
  end

  describe "convert_from_url/2" do
    test "converts spec from URL" do
      # This test would require a real URL, so we'll test error handling
      {:error, reason} =
        OpenApiConverter.convert_from_url("https://invalid-url-that-does-not-exist.com/spec.json")

      assert is_binary(reason)
    end
  end

  describe "convert_from_file/2" do
    test "converts spec from file" do
      # Create a temporary file
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

      file_path = "/tmp/test_spec.json"
      File.write!(file_path, Jason.encode!(spec))

      try do
        {:ok, manual} = OpenApiConverter.convert_from_file(file_path)
        assert manual.name == "Test API"
        assert length(manual.tools) == 1
      after
        File.rm(file_path)
      end
    end

    test "handles file not found" do
      {:error, reason} = OpenApiConverter.convert_from_file("/nonexistent/file.json")
      assert is_binary(reason)
    end
  end

  describe "convert_multiple/2" do
    test "converts multiple specs and merges them" do
      spec1 = %{
        "swagger" => "2.0",
        "info" => %{"title" => "API 1", "version" => "1.0.0"},
        "host" => "api1.example.com",
        "paths" => %{
          "/users" => %{
            "get" => %{
              "operationId" => "getUsers",
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      spec2 = %{
        "swagger" => "2.0",
        "info" => %{"title" => "API 2", "version" => "1.0.0"},
        "host" => "api2.example.com",
        "paths" => %{
          "/products" => %{
            "get" => %{
              "operationId" => "getProducts",
              "responses" => %{"200" => %{"description" => "OK"}}
            }
          }
        }
      }

      {:ok, manual} = OpenApiConverter.convert_multiple([spec1, spec2], prefix: "test")

      assert manual.name == "Merged OpenAPI Tools"
      assert length(manual.tools) == 2

      tool_names = Enum.map(manual.tools, & &1.name)
      assert "test.getUsers" in tool_names
      assert "test.getProducts" in tool_names
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

      {:ok, result} = OpenApiConverter.validate(spec)
      assert result.valid == true
      assert result.version == "2.0"
      assert result.operations_count == 1
    end

    test "validates invalid spec" do
      spec = %{"invalid" => "spec"}

      {:ok, result} = OpenApiConverter.validate(spec)
      assert result.valid == false
      refute Enum.empty?(result.errors)
    end
  end
end
