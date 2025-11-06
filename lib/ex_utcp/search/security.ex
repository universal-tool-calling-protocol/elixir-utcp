defmodule ExUtcp.Search.Security do
  @moduledoc """
  Security scanning for search results using TruffleHog.

  Scans tool definitions and provider configurations for sensitive data
  and provides warnings or filtering capabilities.
  """

  alias ExUtcp.Types
  alias TruffleHog

  @doc """
  Scans tools for sensitive data and returns security warnings.
  """
  @spec scan_tools([Types.tool()]) :: %{String.t() => [map()]}
  def scan_tools(tools) do
    tools
    |> Enum.reduce(%{}, fn tool, acc ->
      warnings = scan_tool(tool)

      if Enum.empty?(warnings) do
        acc
      else
        Map.put(acc, tool.name, warnings)
      end
    end)
  end

  @doc """
  Scans a single tool for sensitive data.
  """
  @spec scan_tool(Types.tool()) :: [map()]
  def scan_tool(tool) do
    warnings = []

    # Scan tool name
    warnings = warnings ++ scan_text(tool.name, "tool_name")

    # Scan tool description
    warnings = warnings ++ scan_text(tool.definition.description, "description")

    # Scan parameters
    warnings =
      if Map.has_key?(tool.definition, :parameters) do
        param_text = Jason.encode!(tool.definition.parameters)
        warnings ++ scan_text(param_text, "parameters")
      else
        warnings
      end

    # Scan response schema
    warnings =
      if Map.has_key?(tool.definition, :response) do
        response_text = Jason.encode!(tool.definition.response)
        warnings ++ scan_text(response_text, "response")
      else
        warnings
      end

    warnings
  end

  @doc """
  Scans providers for sensitive data.
  """
  @spec scan_providers([Types.provider_config()]) :: %{String.t() => [map()]}
  def scan_providers(providers) do
    providers
    |> Enum.reduce(%{}, fn provider, acc ->
      warnings = scan_provider(provider)

      if Enum.empty?(warnings) do
        acc
      else
        Map.put(acc, provider.name, warnings)
      end
    end)
  end

  @doc """
  Scans a single provider for sensitive data.
  """
  @spec scan_provider(Types.provider_config()) :: [map()]
  def scan_provider(provider) do
    warnings = []

    # Scan provider name
    warnings = warnings ++ scan_text(provider.name, "provider_name")

    # Scan URL if present
    warnings =
      if Map.has_key?(provider, :url) do
        warnings ++ scan_text(provider.url, "url")
      else
        warnings
      end

    # Scan headers if present
    warnings =
      if Map.has_key?(provider, :headers) do
        headers_text = Jason.encode!(provider.headers)
        warnings ++ scan_text(headers_text, "headers")
      else
        warnings
      end

    # Scan authentication if present
    warnings =
      if Map.has_key?(provider, :auth) and provider.auth do
        auth_text = Jason.encode!(provider.auth)
        warnings ++ scan_text(auth_text, "auth")
      else
        warnings
      end

    warnings
  end

  @doc """
  Filters search results to exclude tools with sensitive data warnings.
  """
  @spec filter_secure_results([map()]) :: [map()]
  def filter_secure_results(search_results) do
    tools = Enum.map(search_results, & &1.tool)
    security_warnings = scan_tools(tools)

    Enum.filter(search_results, fn result ->
      not Map.has_key?(security_warnings, result.tool.name)
    end)
  end

  @doc """
  Adds security warnings to search results.
  """
  @spec add_security_warnings([map()]) :: [map()]
  def add_security_warnings(search_results) do
    tools = Enum.map(search_results, & &1.tool)
    security_warnings = scan_tools(tools)

    Enum.map(search_results, fn result ->
      warnings = Map.get(security_warnings, result.tool.name, [])
      Map.put(result, :security_warnings, warnings)
    end)
  end

  @doc """
  Checks if a search result contains sensitive data.
  """
  @spec has_sensitive_data?(map()) :: boolean()
  def has_sensitive_data?(search_result) do
    warnings = scan_tool(search_result.tool)
    not Enum.empty?(warnings)
  end

  # Private functions

  defp scan_text(text, field_name) do
    # Use TruffleHog to find sensitive data matches
    matches = TruffleHog.find_matches(text, :all, %{})

    Enum.map(matches, fn match ->
      %{
        field: field_name,
        type: match.type || "unknown",
        value: String.slice(match.value || "", 0, 10) <> "...",
        confidence: match.confidence || 0.8,
        line: match.line || 1
      }
    end)
  rescue
    _ ->
      # Fallback to basic pattern matching if TruffleHog fails
      scan_text_basic(text, field_name)
  end

  defp scan_text_basic(text, field_name) do
    # Basic patterns for common sensitive data
    patterns = [
      {~r/(?i)api[_-]?key[_-]?[:=]\s*["\']?([a-zA-Z0-9_-]{20,})["\']?/, "api_key"},
      {~r/(?i)password[_-]?[:=]\s*["\']?([^\s"']{8,})["\']?/, "password"},
      {~r/(?i)secret[_-]?[:=]\s*["\']?([a-zA-Z0-9_-]{20,})["\']?/, "secret"},
      {~r/(?i)token[_-]?[:=]\s*["\']?([a-zA-Z0-9_-]{20,})["\']?/, "token"},
      {~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, "email"}
    ]

    Enum.flat_map(patterns, fn {pattern, type} ->
      case Regex.scan(pattern, text, capture: :all_but_first) do
        [] ->
          []

        matches ->
          Enum.map(matches, fn match ->
            value =
              case match do
                [val] -> val
                val when is_binary(val) -> val
                _ -> "unknown"
              end

            %{
              field: field_name,
              type: type,
              # Truncate for security
              value: String.slice(value, 0, 10) <> "...",
              confidence: 0.8,
              line: 1
            }
          end)
      end
    end)
  end
end
