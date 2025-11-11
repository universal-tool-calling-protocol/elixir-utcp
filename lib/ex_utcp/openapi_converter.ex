defmodule ExUtcp.OpenApiConverter do
  @moduledoc """
  OpenAPI Converter for automatic API discovery and tool generation.

  Converts OpenAPI 2.0 and 3.0 specifications into UTCP tools, enabling
  AI agents to interact with existing APIs directly without server modifications.

  ## Features

  - OpenAPI 2.0 and 3.0 support
  - Automatic tool generation from API operations
  - Authentication scheme mapping
  - Parameter and response schema handling
  - Variable substitution support
  - Batch processing of multiple specs

  ## Usage

      # Convert from URL
      {:ok, manual} = OpenApiConverter.convert_from_url("https://api.github.com/openapi.json")

      # Convert from local file
      {:ok, manual} = OpenApiConverter.convert_from_file("path/to/spec.json")

      # Convert from map
      {:ok, manual} = OpenApiConverter.convert(spec_map)

      # Convert with custom options
      {:ok, manual} = OpenApiConverter.convert(spec_map, %{
        base_url: "https://api.example.com",
        auth: %{type: "api_key", api_key: "Bearer ${API_KEY}"},
        prefix: "github"
      })
  """

  alias ExUtcp.OpenApiConverter.Generator
  alias ExUtcp.OpenApiConverter.Parser

  @doc """
  Converts an OpenAPI specification to a UTCP manual.

  ## Parameters

  - `spec`: OpenAPI specification as a map
  - `opts`: Optional configuration map with keys:
    - `:base_url` - Override base URL from spec
    - `:auth` - Authentication configuration
    - `:prefix` - Prefix for tool names
    - `:include_deprecated` - Include deprecated operations (default: false)
    - `:filter_tags` - Only include operations with these tags
    - `:exclude_tags` - Exclude operations with these tags

  ## Returns

  `{:ok, manual}` on success, `{:error, reason}` on failure.
  """
  @spec convert(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def convert(spec, opts \\ []) do
    with {:ok, parsed_spec} <- Parser.parse(spec),
         {:ok, tools} <- Generator.generate_tools(parsed_spec, opts) do
      manual = %{
        name: parsed_spec.info.title || "OpenAPI Tools",
        description: parsed_spec.info.description || "Tools generated from OpenAPI specification",
        tools: tools
      }

      {:ok, manual}
    end
  end

  @doc """
  Converts an OpenAPI specification from a URL.

  ## Parameters

  - `url`: URL to the OpenAPI specification
  - `opts`: Optional configuration (same as convert/2)

  ## Returns

  `{:ok, manual}` on success, `{:error, reason}` on failure.
  """
  @spec convert_from_url(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def convert_from_url(url, opts \\ []) do
    with {:ok, response} <- fetch_spec_from_url(url),
         {:ok, spec} <- parse_spec_content(response.body, response.content_type) do
      convert(spec, opts)
    end
  end

  @doc """
  Converts an OpenAPI specification from a local file.

  ## Parameters

  - `file_path`: Path to the OpenAPI specification file
  - `opts`: Optional configuration (same as convert/2)

  ## Returns

  `{:ok, manual}` on success, `{:error, reason}` on failure.
  """
  @spec convert_from_file(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def convert_from_file(file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path),
         {:ok, spec} <- parse_spec_content(content, content_type_from_path(file_path)) do
      convert(spec, opts)
    else
      {:error, :enoent} -> {:error, "File not found: #{file_path}"}
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  @doc """
  Converts multiple OpenAPI specifications and merges them into a single manual.

  ## Parameters

  - `specs`: List of specification sources (maps, URLs, or file paths)
  - `opts`: Optional configuration (same as convert/2)

  ## Returns

  `{:ok, manual}` on success, `{:error, reason}` on failure.
  """
  @spec convert_multiple(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def convert_multiple(specs, opts \\ []) do
    results = Enum.map(specs, &convert_single_spec/1)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil ->
        {_status, manuals} = Enum.unzip(results)
        merged_manual = merge_manuals(manuals, opts)
        {:ok, merged_manual}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates an OpenAPI specification without converting it.

  ## Parameters

  - `spec`: OpenAPI specification as a map

  ## Returns

  `{:ok, validation_result}` on success, `{:error, reason}` on failure.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(spec) do
    Parser.validate(spec)
  end

  # Private functions

  defp convert_single_spec(spec) when is_map(spec) do
    convert(spec)
  end

  defp convert_single_spec(url) when is_binary(url) do
    convert_from_url(url)
  end

  defp convert_single_spec(file_path) when is_binary(file_path) do
    convert_from_file(file_path)
  end

  defp fetch_spec_from_url(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, response} ->
        # Extract content type from headers
        content_type =
          case response.headers["content-type"] do
            [content_type | _] -> content_type
            content_type when is_binary(content_type) -> content_type
            _ -> "application/json"
          end

        {:ok, %{body: response.body, content_type: content_type}}

      {:error, reason} ->
        {:error, "Failed to fetch spec from URL: #{inspect(reason)}"}
    end
  end

  defp parse_spec_content(content, content_type) do
    content_str = ensure_string(content)

    case content_type do
      "application/json" -> parse_json(content_str)
      "application/yaml" -> parse_yaml(content_str)
      _ -> try_parse_both_formats(content_str)
    end
  end

  defp ensure_string(content) do
    if is_binary(content), do: content, else: inspect(content)
  end

  defp parse_json(content_str) do
    case Jason.decode(content_str) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  defp parse_yaml(content_str) do
    case YamlElixir.read_from_string(content_str) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, "Invalid YAML: #{inspect(reason)}"}
    end
  end

  defp try_parse_both_formats(content_str) do
    case parse_json(content_str) do
      {:ok, spec} -> {:ok, spec}
      {:error, _} -> parse_yaml_or_error(content_str)
    end
  end

  defp parse_yaml_or_error(content_str) do
    case YamlElixir.read_from_string(content_str) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, "Invalid spec format: #{inspect(reason)}"}
    end
  end

  defp content_type_from_path(path) do
    case Path.extname(path) do
      ".yaml" -> "application/yaml"
      ".yml" -> "application/yaml"
      _ -> "application/json"
    end
  end

  defp merge_manuals(manuals, opts) do
    all_tools = Enum.flat_map(manuals, & &1.tools)
    prefix = Keyword.get(opts, :prefix, "")

    prefixed_tools =
      if prefix == "" do
        all_tools
      else
        Enum.map(all_tools, fn tool ->
          %{tool | name: "#{prefix}.#{tool.name}"}
        end)
      end

    %{
      name: "Merged OpenAPI Tools",
      description: "Tools generated from multiple OpenAPI specifications",
      tools: prefixed_tools
    }
  end
end
