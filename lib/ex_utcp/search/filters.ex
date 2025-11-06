defmodule ExUtcp.Search.Filters do
  @moduledoc """
  Search filters for UTCP tools and providers.

  Provides filtering capabilities based on various criteria.
  """

  alias ExUtcp.Types

  @doc """
  Applies filters to a list of tools.
  """
  @spec apply_filters([Types.tool()], map()) :: [Types.tool()]
  def apply_filters(tools, filters) do
    tools
    |> filter_by_providers(Map.get(filters, :providers, []))
    |> filter_by_transports(Map.get(filters, :transports, []))
    |> filter_by_tags(Map.get(filters, :tags, []))
  end

  @doc """
  Applies filters to a list of providers.
  """
  @spec apply_provider_filters([Types.provider_config()], map()) :: [Types.provider_config()]
  def apply_provider_filters(providers, filters) do
    providers
    |> filter_providers_by_names(Map.get(filters, :providers, []))
    |> filter_providers_by_transports(Map.get(filters, :transports, []))
  end

  @doc """
  Filters tools by provider names.
  """
  @spec filter_by_providers([Types.tool()], [String.t()]) :: [Types.tool()]
  def filter_by_providers(tools, []), do: tools

  def filter_by_providers(tools, provider_names) do
    provider_set = MapSet.new(provider_names)

    Enum.filter(tools, fn tool ->
      MapSet.member?(provider_set, tool.provider_name)
    end)
  end

  @doc """
  Filters tools by transport types.
  """
  @spec filter_by_transports([Types.tool()], [atom()]) :: [Types.tool()]
  def filter_by_transports(tools, []), do: tools

  def filter_by_transports(tools, transport_types) do
    transport_set = MapSet.new(transport_types)

    # This would require access to provider information
    # For now, we'll implement a basic filter based on provider naming conventions
    Enum.filter(tools, fn tool ->
      # Extract transport type from provider name or use a lookup
      provider_transport = infer_transport_from_provider(tool.provider_name)
      MapSet.member?(transport_set, provider_transport)
    end)
  end

  @doc """
  Filters tools by tags.
  """
  @spec filter_by_tags([Types.tool()], [String.t()]) :: [Types.tool()]
  def filter_by_tags(tools, []), do: tools

  def filter_by_tags(tools, tags) do
    tag_set = MapSet.new(tags)

    Enum.filter(tools, fn tool ->
      tool_tags = extract_tool_tags(tool)
      not MapSet.disjoint?(tag_set, MapSet.new(tool_tags))
    end)
  end

  @doc """
  Filters providers by names.
  """
  @spec filter_providers_by_names([Types.provider_config()], [String.t()]) :: [
          Types.provider_config()
        ]
  def filter_providers_by_names(providers, []), do: providers

  def filter_providers_by_names(providers, names) do
    name_set = MapSet.new(names)

    Enum.filter(providers, fn provider ->
      MapSet.member?(name_set, provider.name)
    end)
  end

  @doc """
  Filters providers by transport types.
  """
  @spec filter_providers_by_transports([Types.provider_config()], [atom()]) :: [
          Types.provider_config()
        ]
  def filter_providers_by_transports(providers, []), do: providers

  def filter_providers_by_transports(providers, transport_types) do
    transport_set = MapSet.new(transport_types)

    Enum.filter(providers, fn provider ->
      MapSet.member?(transport_set, provider.type)
    end)
  end

  @doc """
  Creates a filter for tools with specific capabilities.
  """
  @spec capability_filter([String.t()]) :: (Types.tool() -> boolean())
  def capability_filter(capabilities) do
    capability_set = MapSet.new(capabilities)

    fn tool ->
      tool_capabilities = extract_tool_capabilities(tool)
      not MapSet.disjoint?(capability_set, MapSet.new(tool_capabilities))
    end
  end

  @doc """
  Creates a filter for tools with specific parameter types.
  """
  @spec parameter_type_filter([String.t()]) :: (Types.tool() -> boolean())
  def parameter_type_filter(param_types) do
    type_set = MapSet.new(param_types)

    fn tool ->
      tool_param_types = extract_parameter_types(tool)
      not MapSet.disjoint?(type_set, MapSet.new(tool_param_types))
    end
  end

  @doc """
  Creates a filter for tools with specific response types.
  """
  @spec response_type_filter([String.t()]) :: (Types.tool() -> boolean())
  def response_type_filter(response_types) do
    type_set = MapSet.new(response_types)

    fn tool ->
      tool_response_types = extract_response_types(tool)
      not MapSet.disjoint?(type_set, MapSet.new(tool_response_types))
    end
  end

  # Private functions

  defp infer_transport_from_provider(provider_name) do
    cond do
      String.contains?(provider_name, "http") ->
        :http

      String.contains?(provider_name, "websocket") or String.contains?(provider_name, "ws") ->
        :websocket

      String.contains?(provider_name, "grpc") ->
        :grpc

      String.contains?(provider_name, "graphql") ->
        :graphql

      String.contains?(provider_name, "mcp") ->
        :mcp

      String.contains?(provider_name, "tcp") ->
        :tcp

      String.contains?(provider_name, "udp") ->
        :udp

      String.contains?(provider_name, "cli") ->
        :cli

      true ->
        :unknown
    end
  end

  defp extract_tool_tags(tool) do
    # Extract tags from tool definition or infer from description
    tags = []

    # Check if tool definition has explicit tags
    tags =
      case tool.definition do
        %{tags: explicit_tags} when is_list(explicit_tags) -> explicit_tags
        _ -> tags
      end

    # Infer tags from description if no explicit tags
    if Enum.empty?(tags) do
      infer_tags_from_description(tool.definition.description)
    else
      tags
    end
  end

  defp extract_tool_capabilities(tool) do
    # Extract capabilities from tool definition
    capabilities = []

    # Infer capabilities from parameters and responses
    capabilities =
      if Map.has_key?(tool.definition, :parameters) do
        param_capabilities = infer_capabilities_from_parameters(tool.definition.parameters)
        capabilities ++ param_capabilities
      else
        capabilities
      end

    capabilities =
      if Map.has_key?(tool.definition, :response) do
        response_capabilities = infer_capabilities_from_response(tool.definition.response)
        capabilities ++ response_capabilities
      else
        capabilities
      end

    capabilities
  end

  defp extract_parameter_types(tool) do
    case tool.definition do
      %{parameters: %{"properties" => properties}} ->
        properties
        |> Enum.map(fn {_name, param_def} ->
          Map.get(param_def, "type", "unknown")
        end)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp extract_response_types(tool) do
    case tool.definition do
      %{response: %{"properties" => properties}} ->
        properties
        |> Enum.map(fn {_name, field_def} ->
          Map.get(field_def, "type", "unknown")
        end)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp infer_tags_from_description(description) do
    # Simple tag inference based on common patterns
    description_lower = String.downcase(description)

    tags = []

    tags =
      if String.contains?(description_lower, ["file", "document", "pdf", "image"]) do
        ["file-processing" | tags]
      else
        tags
      end

    tags =
      if String.contains?(description_lower, ["api", "http", "request", "endpoint"]) do
        ["api" | tags]
      else
        tags
      end

    tags =
      if String.contains?(description_lower, ["data", "database", "query", "sql"]) do
        ["data" | tags]
      else
        tags
      end

    tags =
      if String.contains?(description_lower, ["text", "string", "parse", "format"]) do
        ["text-processing" | tags]
      else
        tags
      end

    tags =
      if String.contains?(description_lower, ["network", "connection", "socket", "tcp", "udp"]) do
        ["network" | tags]
      else
        tags
      end

    tags
  end

  defp infer_capabilities_from_parameters(parameters) when is_map(parameters) do
    properties = Map.get(parameters, "properties", %{})

    capabilities = []

    # Infer capabilities from parameter names and types
    capabilities =
      if Map.has_key?(properties, "file") or Map.has_key?(properties, "path") do
        ["file-handling" | capabilities]
      else
        capabilities
      end

    capabilities =
      if Map.has_key?(properties, "url") or Map.has_key?(properties, "endpoint") do
        ["web-requests" | capabilities]
      else
        capabilities
      end

    capabilities =
      if Map.has_key?(properties, "query") or Map.has_key?(properties, "search") do
        ["search" | capabilities]
      else
        capabilities
      end

    capabilities
  end

  defp infer_capabilities_from_parameters(_), do: []

  defp infer_capabilities_from_response(response) when is_map(response) do
    properties = Map.get(response, "properties", %{})

    capabilities = []

    # Infer capabilities from response structure
    capabilities =
      if Map.has_key?(properties, "data") or Map.has_key?(properties, "result") do
        ["data-retrieval" | capabilities]
      else
        capabilities
      end

    capabilities =
      if Map.has_key?(properties, "status") or Map.has_key?(properties, "success") do
        ["status-reporting" | capabilities]
      else
        capabilities
      end

    capabilities
  end

  defp infer_capabilities_from_response(_), do: []
end
