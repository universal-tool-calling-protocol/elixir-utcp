defmodule ExUtcp.OpenApiConverter.Generator do
  @moduledoc """
  Generates UTCP tools from parsed OpenAPI specifications.
  """

  alias ExUtcp.OpenApiConverter.Types, as: T
  alias ExUtcp.OpenApiConverter.{AuthMapper}

  @doc """
  Generates UTCP tools from a parsed OpenAPI specification.

  ## Parameters

  - `parsed_spec`: Parsed OpenAPI specification
  - `opts`: Conversion options

  ## Returns

  `{:ok, tools}` on success, `{:error, reason}` on failure.
  """
  @spec generate_tools(T.ParsedSpec.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def generate_tools(parsed_spec, opts \\ []) do
    conversion_opts = build_conversion_options(opts)

    tools =
      parsed_spec.paths
      |> Enum.flat_map(&generate_tools_from_path(&1, parsed_spec, conversion_opts))
      |> Enum.filter(&filter_tool(&1, conversion_opts))
      |> Enum.map(&apply_prefix(&1, conversion_opts.prefix))

    {:ok, tools}
  rescue
    error -> {:error, "Failed to generate tools: #{inspect(error)}"}
  end

  # Private functions

  defp build_conversion_options(opts) do
    %T.ConversionOptions{
      base_url: Keyword.get(opts, :base_url),
      auth: Keyword.get(opts, :auth),
      prefix: Keyword.get(opts, :prefix, ""),
      include_deprecated: Keyword.get(opts, :include_deprecated, false),
      filter_tags: Keyword.get(opts, :filter_tags, []),
      exclude_tags: Keyword.get(opts, :exclude_tags, []),
      custom_headers: Keyword.get(opts, :custom_headers, %{}),
      timeout: Keyword.get(opts, :timeout, 30_000)
    }
  end

  defp generate_tools_from_path(path, parsed_spec, opts) do
    Enum.map(path.operations, fn operation ->
      generate_tool_from_operation(operation, parsed_spec, opts)
    end)
  end

  defp generate_tool_from_operation(operation, parsed_spec, opts) do
    tool_name = generate_tool_name(operation, opts.prefix)

    %{
      name: tool_name,
      description: build_tool_description(operation),
      input_schema: build_input_schema(operation),
      output_schema: build_output_schema(operation),
      provider: build_provider(operation, parsed_spec, opts)
    }
  end

  defp generate_tool_name(operation, _prefix) do
    operation.operation_id ||
      "#{operation.method}_#{sanitize_path(operation.path)}"
  end

  defp sanitize_path(path) do
    path
    |> String.replace(~r/[{}]/, "")
    |> String.replace(~r/[^a-zA-Z0-9]/, "_")
    |> String.downcase()
  end

  defp build_tool_description(operation) do
    description_parts = []

    description_parts =
      if operation.summary do
        [operation.summary | description_parts]
      else
        description_parts
      end

    description_parts =
      if operation.description do
        [operation.description | description_parts]
      else
        description_parts
      end

    description_parts =
      if operation.deprecated do
        ["[DEPRECATED]" | description_parts]
      else
        description_parts
      end

    case description_parts do
      [] -> "#{String.upcase(operation.method)} #{operation.path}"
      parts -> Enum.join(Enum.reverse(parts), " - ")
    end
  end

  defp build_input_schema(operation) do
    properties = %{}
    required = []

    # Add path parameters
    {properties, required} = add_path_parameters(operation, properties, required)

    # Add query parameters
    {properties, required} = add_query_parameters(operation, properties, required)

    # Add header parameters
    {properties, required} = add_header_parameters(operation, properties, required)

    # Add request body
    {properties, required} = add_request_body(operation, properties, required)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
  end

  defp add_path_parameters(operation, properties, required) do
    path_params = Enum.filter(operation.parameters, &(&1.in == "path"))

    {new_properties, new_required} =
      Enum.reduce(path_params, {properties, required}, fn param, {props, req} ->
        param_schema = build_parameter_schema(param)
        new_props = Map.put(props, param.name, param_schema)
        new_req = if param.required, do: [param.name | req], else: req
        {new_props, new_req}
      end)

    {new_properties, new_required}
  end

  defp add_query_parameters(operation, properties, required) do
    query_params = Enum.filter(operation.parameters, &(&1.in == "query"))

    {new_properties, new_required} =
      Enum.reduce(query_params, {properties, required}, fn param, {props, req} ->
        param_schema = build_parameter_schema(param)
        new_props = Map.put(props, param.name, param_schema)
        new_req = if param.required, do: [param.name | req], else: req
        {new_props, new_req}
      end)

    {new_properties, new_required}
  end

  defp add_header_parameters(operation, properties, required) do
    header_params = Enum.filter(operation.parameters, &(&1.in == "header"))

    {new_properties, new_required} =
      Enum.reduce(header_params, {properties, required}, fn param, {props, req} ->
        param_schema = build_parameter_schema(param)
        new_props = Map.put(props, param.name, param_schema)
        new_req = if param.required, do: [param.name | req], else: req
        {new_props, new_req}
      end)

    {new_properties, new_required}
  end

  defp add_request_body(operation, properties, required) do
    case operation.request_body do
      nil ->
        {properties, required}

      request_body ->
        body_schema = build_request_body_schema(request_body)
        new_props = Map.put(properties, "body", body_schema)
        new_req = if request_body.required, do: ["body" | required], else: required
        {new_props, new_req}
    end
  end

  defp build_parameter_schema(param) do
    base_schema =
      case param.schema do
        nil -> %{"type" => "string"}
        schema -> convert_schema_to_json_schema(schema)
      end

    base_schema
    |> Map.put("description", param.description)
    |> Map.put("example", param.example)
  end

  defp build_request_body_schema(request_body) do
    case request_body.schema do
      nil -> %{"type" => "object"}
      schema -> convert_schema_to_json_schema(schema)
    end
    |> Map.put("description", request_body.description)
  end

  defp convert_schema_to_json_schema(nil), do: %{"type" => "string"}

  defp convert_schema_to_json_schema(schema) do
    base_schema = %{
      "type" => schema.type || "string",
      "description" => schema.description,
      "example" => schema.example
    }

    base_schema =
      if schema.format do
        Map.put(base_schema, "format", schema.format)
      else
        base_schema
      end

    base_schema =
      if schema.enum do
        Map.put(base_schema, "enum", schema.enum)
      else
        base_schema
      end

    base_schema =
      if schema.properties && map_size(schema.properties) > 0 do
        converted_props =
          Enum.map(schema.properties, fn {name, prop_schema} ->
            {name, convert_schema_to_json_schema(prop_schema)}
          end)
          |> Map.new()

        base_schema
        |> Map.put("properties", converted_props)
        |> Map.put("required", schema.required || [])
      else
        base_schema
      end

    base_schema =
      if schema.items do
        Map.put(base_schema, "items", convert_schema_to_json_schema(schema.items))
      else
        base_schema
      end

    base_schema
  end

  defp build_output_schema(operation) do
    case operation.responses do
      [] ->
        %{"type" => "object"}

      responses ->
        # Find the first successful response (2xx)
        success_response =
          Enum.find(responses, fn response ->
            String.starts_with?(response.status_code, "2")
          end)

        case success_response do
          nil -> %{"type" => "object"}
          response -> build_response_schema(response)
        end
    end
  end

  defp build_response_schema(response) do
    case response.schema do
      nil -> %{"type" => "object"}
      schema -> convert_schema_to_json_schema(schema)
    end
    |> Map.put("description", response.description)
  end

  defp build_provider(operation, parsed_spec, opts) do
    base_url = opts.base_url || get_base_url(parsed_spec)
    auth = opts.auth || build_auth_from_security(operation, parsed_spec)

    %{
      name: "openapi_#{operation.operation_id}",
      type: :http,
      http_method: String.upcase(operation.method),
      url: build_url(base_url, operation.path),
      content_type: "application/json",
      auth: auth,
      headers: opts.custom_headers
    }
  end

  defp get_base_url(parsed_spec) do
    case parsed_spec.servers do
      [server | _] -> server.url
      [] -> "http://localhost"
    end
  end

  defp build_url(base_url, path) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end

  defp build_auth_from_security(operation, parsed_spec) do
    case operation.security do
      [] ->
        nil

      [security_requirement | _] ->
        AuthMapper.map_security_requirement(
          security_requirement,
          parsed_spec.components.security_schemes
        )

      _ ->
        nil
    end
  end

  defp filter_tool(tool, opts) do
    # Check if tool should be included based on tags
    tool_tags = extract_tool_tags(tool)

    # Check filter_tags
    if opts.filter_tags == [] do
      true
    else
      if Enum.any?(opts.filter_tags, &(&1 in tool_tags)) do
        true
      else
        false
      end
    end
    |> then(fn include_by_filter ->
      # Check exclude_tags
      if opts.exclude_tags == [] do
        include_by_filter
      else
        if Enum.any?(opts.exclude_tags, &(&1 in tool_tags)) do
          false
        else
          include_by_filter
        end
      end
    end)
    |> then(fn include_by_tags ->
      # Check deprecated
      if opts.include_deprecated do
        include_by_tags
      else
        include_by_tags && !String.contains?(tool.description, "[DEPRECATED]")
      end
    end)
  end

  defp extract_tool_tags(_tool) do
    # Extract tags from tool name or description
    # This is a simplified implementation
    []
  end

  defp apply_prefix(tool, ""), do: tool

  defp apply_prefix(tool, prefix) do
    %{tool | name: "#{prefix}.#{tool.name}"}
  end
end
