defmodule ExUtcp.OpenApiConverter.Parser do
  @moduledoc """
  OpenAPI specification parser for both 2.0 and 3.0 versions.
  """

  alias ExUtcp.OpenApiConverter.Types, as: T

  @doc """
  Parses an OpenAPI specification into a normalized structure.

  ## Parameters

  - `spec`: OpenAPI specification as a map

  ## Returns

  `{:ok, parsed_spec}` on success, `{:error, reason}` on failure.
  """
  @spec parse(map()) :: {:ok, T.ParsedSpec.t()} | {:error, term()}
  def parse(spec) do
    case detect_version(spec) do
      "2.0" -> parse_swagger_2_0(spec)
      "3.0" -> parse_openapi_3_0(spec)
      version -> {:error, "Unsupported OpenAPI version: #{version}"}
    end
  end

  @doc """
  Validates an OpenAPI specification.

  ## Parameters

  - `spec`: OpenAPI specification as a map

  ## Returns

  `{:ok, validation_result}` on success, `{:error, reason}` on failure.
  """
  @spec validate(map()) :: {:ok, T.ValidationResult.t()} | {:error, term()}
  def validate(spec) do
    case parse(spec) do
      {:ok, parsed_spec} ->
        validation_result = %T.ValidationResult{
          valid: true,
          errors: [],
          warnings: [],
          version: parsed_spec.version,
          operations_count: count_operations(parsed_spec),
          security_schemes_count: count_security_schemes(parsed_spec)
        }

        {:ok, validation_result}

      {:error, reason} ->
        validation_result = %T.ValidationResult{
          valid: false,
          errors: [%T.ValidationError{path: "", message: inspect(reason), code: "PARSE_ERROR"}],
          warnings: [],
          version: nil,
          operations_count: 0,
          security_schemes_count: 0
        }

        {:ok, validation_result}
    end
  end

  # Private functions

  defp detect_version(spec) do
    cond do
      Map.has_key?(spec, "openapi") -> "3.0"
      Map.has_key?(spec, "swagger") -> "2.0"
      true -> "unknown"
    end
  end

  defp parse_swagger_2_0(spec) do
    parsed_spec = %T.ParsedSpec{
      version: "2.0",
      info: parse_swagger_info(spec["info"] || %{}),
      servers: parse_swagger_servers(spec),
      paths: parse_swagger_paths(spec["paths"] || %{}),
      components: parse_swagger_components(spec),
      security: parse_swagger_security(spec["security"] || []),
      tags: parse_swagger_tags(spec["tags"] || []),
      external_docs: parse_external_docs(spec["externalDocs"])
    }

    {:ok, parsed_spec}
  rescue
    error ->
      {:error, "Failed to parse Swagger 2.0 spec: #{Exception.message(error)}"}
  end

  defp parse_openapi_3_0(spec) do
    parsed_spec = %T.ParsedSpec{
      version: "3.0",
      info: parse_openapi_info(spec["info"] || %{}),
      servers: parse_openapi_servers(spec["servers"] || []),
      paths: parse_openapi_paths(spec["paths"] || %{}),
      components: parse_openapi_components(spec["components"] || %{}),
      security: parse_openapi_security(spec["security"] || []),
      tags: parse_openapi_tags(spec["tags"] || []),
      external_docs: parse_external_docs(spec["externalDocs"])
    }

    {:ok, parsed_spec}
  rescue
    error -> {:error, "Failed to parse OpenAPI 3.0 spec: #{Exception.message(error)}"}
  end

  # Swagger 2.0 parsing functions

  defp parse_swagger_info(info) do
    %T.ParsedInfo{
      title: info["title"] || "API",
      description: info["description"],
      version: info["version"] || "1.0.0",
      contact: parse_contact(info["contact"]),
      license: parse_license(info["license"])
    }
  end

  defp parse_swagger_servers(spec) do
    host = spec["host"] || "localhost"
    base_path = spec["basePath"] || ""
    schemes = spec["schemes"] || ["http"]

    Enum.map(schemes, fn scheme ->
      %T.ParsedServer{
        url: "#{scheme}://#{host}#{base_path}",
        description: nil,
        variables: %{}
      }
    end)
  end

  defp parse_swagger_paths(paths) do
    Enum.map(paths, fn {path, path_item} ->
      operations = parse_swagger_operations(path, path_item)
      %T.ParsedPath{path: path, operations: operations}
    end)
  end

  defp parse_swagger_operations(path, path_item) do
    operations = []

    operations =
      if path_item["get"] do
        [parse_swagger_operation("GET", path, path_item["get"]) | operations]
      else
        operations
      end

    operations =
      if path_item["post"] do
        [parse_swagger_operation("POST", path, path_item["post"]) | operations]
      else
        operations
      end

    operations =
      if path_item["put"] do
        [parse_swagger_operation("PUT", path, path_item["put"]) | operations]
      else
        operations
      end

    operations =
      if path_item["delete"] do
        [parse_swagger_operation("DELETE", path, path_item["delete"]) | operations]
      else
        operations
      end

    operations =
      if path_item["patch"] do
        [parse_swagger_operation("PATCH", path, path_item["patch"]) | operations]
      else
        operations
      end

    operations =
      if path_item["head"] do
        [parse_swagger_operation("HEAD", path, path_item["head"]) | operations]
      else
        operations
      end

    operations =
      if path_item["options"] do
        [parse_swagger_operation("OPTIONS", path, path_item["options"]) | operations]
      else
        operations
      end

    Enum.reverse(operations)
  end

  defp parse_swagger_operation(method, path, operation) do
    %T.ParsedOperation{
      method: String.downcase(method),
      path: path,
      operation_id: operation["operationId"] || generate_operation_id(method, path),
      summary: operation["summary"],
      description: operation["description"],
      tags: operation["tags"] || [],
      parameters: parse_swagger_parameters(operation["parameters"] || []),
      # Swagger 2.0 doesn't have request body
      request_body: nil,
      responses: parse_swagger_responses(operation["responses"] || %{}),
      security: parse_swagger_operation_security(operation["security"]),
      deprecated: operation["deprecated"] || false
    }
  end

  defp parse_swagger_parameters(parameters) do
    Enum.map(parameters, fn param ->
      %T.ParsedParameter{
        name: param["name"],
        in: param["in"],
        description: param["description"],
        required: param["required"] || false,
        schema: parse_swagger_schema(param["schema"] || %{"type" => param["type"]}),
        style: nil,
        explode: nil,
        example: param["example"]
      }
    end)
  end

  defp parse_swagger_responses(responses) do
    Enum.map(responses, fn {status_code, response} ->
      %T.ParsedResponse{
        status_code: status_code,
        description: response["description"],
        # Swagger 2.0 default
        content_types: ["application/json"],
        schema: parse_swagger_schema(response["schema"])
      }
    end)
  end

  defp parse_swagger_schema(schema) when is_map(schema) do
    items = if schema["items"], do: parse_swagger_schema(schema["items"])

    %T.OpenApiSchema{
      type: schema["type"],
      format: schema["format"],
      title: schema["title"],
      description: schema["description"],
      required: schema["required"] || [],
      properties: parse_swagger_properties(schema["properties"] || %{}),
      items: items,
      enum: schema["enum"],
      example: schema["example"]
    }
  end

  defp parse_swagger_schema(_), do: nil

  defp parse_swagger_properties(properties) do
    Enum.map(properties, fn {name, schema} ->
      {name, parse_swagger_schema(schema)}
    end)
    |> Map.new()
  end

  defp parse_swagger_components(spec) do
    %{
      security_schemes: parse_swagger_security_definitions(spec["securityDefinitions"] || %{})
    }
  end

  defp parse_swagger_security_definitions(security_definitions) do
    Enum.map(security_definitions, fn {name, scheme} ->
      {name,
       %T.ParsedSecurityScheme{
         name: scheme["name"],
         type: scheme["type"],
         description: scheme["description"],
         in: scheme["in"],
         scheme: scheme["scheme"],
         bearer_format: scheme["bearerFormat"],
         flows: nil
       }}
    end)
    |> Map.new()
  end

  defp parse_swagger_security(security) do
    Enum.map(security, fn security_requirement ->
      Enum.map(security_requirement, fn {name, scopes} ->
        {name, scopes || []}
      end)
      |> Map.new()
    end)
  end

  defp parse_swagger_operation_security(nil), do: []
  defp parse_swagger_operation_security(security), do: parse_swagger_security(security)

  defp parse_swagger_tags(tags) do
    Enum.map(tags, fn tag ->
      %T.Tag{
        name: tag["name"],
        description: tag["description"],
        external_docs: parse_external_docs(tag["externalDocs"])
      }
    end)
  end

  # OpenAPI 3.0 parsing functions

  defp parse_openapi_info(info) do
    %T.ParsedInfo{
      title: info["title"] || "API",
      description: info["description"],
      version: info["version"] || "1.0.0",
      contact: parse_contact(info["contact"]),
      license: parse_license(info["license"])
    }
  end

  defp parse_openapi_servers(servers) do
    Enum.map(servers, fn server ->
      %T.ParsedServer{
        url: server["url"] || "/",
        description: server["description"],
        variables: server["variables"] || %{}
      }
    end)
  end

  defp parse_openapi_paths(paths) do
    Enum.map(paths, fn {path, path_item} ->
      operations = parse_openapi_operations(path, path_item)
      %T.ParsedPath{path: path, operations: operations}
    end)
  end

  defp parse_openapi_operations(path, path_item) do
    operations = []

    operations =
      if path_item["get"] do
        [parse_openapi_operation("GET", path, path_item["get"]) | operations]
      else
        operations
      end

    operations =
      if path_item["post"] do
        [parse_openapi_operation("POST", path, path_item["post"]) | operations]
      else
        operations
      end

    operations =
      if path_item["put"] do
        [parse_openapi_operation("PUT", path, path_item["put"]) | operations]
      else
        operations
      end

    operations =
      if path_item["delete"] do
        [parse_openapi_operation("DELETE", path, path_item["delete"]) | operations]
      else
        operations
      end

    operations =
      if path_item["patch"] do
        [parse_openapi_operation("PATCH", path, path_item["patch"]) | operations]
      else
        operations
      end

    operations =
      if path_item["head"] do
        [parse_openapi_operation("HEAD", path, path_item["head"]) | operations]
      else
        operations
      end

    operations =
      if path_item["options"] do
        [parse_openapi_operation("OPTIONS", path, path_item["options"]) | operations]
      else
        operations
      end

    operations =
      if path_item["trace"] do
        [parse_openapi_operation("TRACE", path, path_item["trace"]) | operations]
      else
        operations
      end

    Enum.reverse(operations)
  end

  defp parse_openapi_operation(method, path, operation) do
    %T.ParsedOperation{
      method: String.downcase(method),
      path: path,
      operation_id: operation["operationId"] || generate_operation_id(method, path),
      summary: operation["summary"],
      description: operation["description"],
      tags: operation["tags"] || [],
      parameters: parse_openapi_parameters(operation["parameters"] || []),
      request_body: parse_openapi_request_body(operation["requestBody"]),
      responses: parse_openapi_responses(operation["responses"] || %{}),
      security: parse_openapi_operation_security(operation["security"]),
      deprecated: operation["deprecated"] || false
    }
  end

  defp parse_openapi_parameters(parameters) do
    Enum.map(parameters, fn param ->
      %T.ParsedParameter{
        name: param["name"],
        in: param["in"],
        description: param["description"],
        required: param["required"] || false,
        schema: parse_openapi_schema(param["schema"]),
        style: param["style"],
        explode: param["explode"],
        example: param["example"]
      }
    end)
  end

  defp parse_openapi_request_body(nil), do: nil

  defp parse_openapi_request_body(request_body) do
    %T.ParsedRequestBody{
      description: request_body["description"],
      required: request_body["required"] || false,
      content_types: Map.keys(request_body["content"] || %{}),
      schema: parse_openapi_media_types(request_body["content"] || %{})
    }
  end

  defp parse_openapi_responses(responses) do
    Enum.map(responses, fn {status_code, response} ->
      %T.ParsedResponse{
        status_code: status_code,
        description: response["description"],
        content_types: Map.keys(response["content"] || %{}),
        schema: parse_openapi_media_types(response["content"] || %{})
      }
    end)
  end

  defp parse_openapi_media_types(content) do
    case Map.values(content) do
      [media_type | _] -> parse_openapi_schema(media_type["schema"])
      [] -> nil
    end
  end

  defp parse_openapi_schema(nil), do: nil

  defp parse_openapi_schema(schema) when is_map(schema) do
    %T.OpenApiSchema{
      type: schema["type"],
      format: schema["format"],
      title: schema["title"],
      description: schema["description"],
      required: schema["required"] || [],
      properties: parse_openapi_properties(schema["properties"] || %{}),
      items: parse_openapi_schema(schema["items"]),
      enum: schema["enum"],
      example: schema["example"]
    }
  end

  defp parse_openapi_properties(properties) do
    Enum.map(properties, fn {name, schema} ->
      {name, parse_openapi_schema(schema)}
    end)
    |> Map.new()
  end

  defp parse_openapi_components(components) do
    %{
      security_schemes: parse_openapi_security_schemes(components["securitySchemes"] || %{})
    }
  end

  defp parse_openapi_security_schemes(security_schemes) do
    Enum.map(security_schemes, fn {name, scheme} ->
      %T.ParsedSecurityScheme{
        name: name,
        type: scheme["type"],
        description: scheme["description"],
        in: scheme["in"],
        scheme: scheme["scheme"],
        bearer_format: scheme["bearerFormat"],
        flows: parse_oauth_flows(scheme["flows"])
      }
    end)
    |> Map.new()
  end

  defp parse_oauth_flows(nil), do: nil

  defp parse_oauth_flows(flows) do
    %T.OpenApiOAuthFlows{
      implicit: parse_oauth_flow(flows["implicit"]),
      password: parse_oauth_flow(flows["password"]),
      client_credentials: parse_oauth_flow(flows["clientCredentials"]),
      authorization_code: parse_oauth_flow(flows["authorizationCode"])
    }
  end

  defp parse_oauth_flow(nil), do: nil

  defp parse_oauth_flow(flow) do
    %T.OpenApiOAuthFlow{
      authorization_url: flow["authorizationUrl"],
      token_url: flow["tokenUrl"],
      refresh_url: flow["refreshUrl"],
      scopes: flow["scopes"] || %{}
    }
  end

  defp parse_openapi_security(security) do
    Enum.map(security, fn security_requirement ->
      Enum.map(security_requirement, fn {name, scopes} ->
        {name, scopes || []}
      end)
      |> Map.new()
    end)
  end

  defp parse_openapi_operation_security(nil), do: []
  defp parse_openapi_operation_security(security), do: parse_openapi_security(security)

  defp parse_openapi_tags(tags) do
    Enum.map(tags, fn tag ->
      %T.Tag{
        name: tag["name"],
        description: tag["description"],
        external_docs: parse_external_docs(tag["externalDocs"])
      }
    end)
  end

  # Common parsing functions

  defp parse_contact(nil), do: nil

  defp parse_contact(contact) do
    %T.Contact{
      name: contact["name"],
      url: contact["url"],
      email: contact["email"]
    }
  end

  defp parse_license(nil), do: nil

  defp parse_license(license) do
    %T.License{
      name: license["name"],
      url: license["url"]
    }
  end

  defp parse_external_docs(nil), do: nil

  defp parse_external_docs(external_docs) do
    %T.ExternalDocs{
      description: external_docs["description"],
      url: external_docs["url"]
    }
  end

  defp generate_operation_id(method, path) do
    path
    |> String.replace(~r/[{}]/, "")
    |> String.replace(~r/[^a-zA-Z0-9]/, "_")
    # Replace multiple underscores with single underscore
    |> String.replace(~r/_{2,}/, "_")
    # Remove leading/trailing underscores
    |> String.replace(~r/^_|_$/, "")
    |> String.downcase()
    |> then(&"#{String.downcase(method)}_#{&1}")
  end

  defp count_operations(parsed_spec) do
    Enum.reduce(parsed_spec.paths, 0, fn path, acc ->
      acc + length(path.operations)
    end)
  end

  defp count_security_schemes(parsed_spec) do
    map_size(parsed_spec.components.security_schemes)
  end
end
