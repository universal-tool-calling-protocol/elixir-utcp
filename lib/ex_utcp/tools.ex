defmodule ExUtcp.Tools do
  @moduledoc """
  Tool definitions and management for UTCP.

  This module handles tool schemas, registration, and discovery.
  """

  alias ExUtcp.Types, as: T

  @doc """
  Creates a new tool input/output schema.
  """
  @spec new_schema(keyword()) :: T.tool_input_output_schema()
  def new_schema(opts \\ []) do
    %{
      type: Keyword.get(opts, :type, "object"),
      properties: Keyword.get(opts, :properties, %{}),
      required: Keyword.get(opts, :required, []),
      description: Keyword.get(opts, :description, ""),
      title: Keyword.get(opts, :title, ""),
      items: Keyword.get(opts, :items, %{}),
      enum: Keyword.get(opts, :enum, []),
      minimum: Keyword.get(opts, :minimum, nil),
      maximum: Keyword.get(opts, :maximum, nil),
      format: Keyword.get(opts, :format, "")
    }
  end

  @doc """
  Creates a new tool definition.
  """
  @spec new_tool(keyword()) :: T.tool()
  def new_tool(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description, ""),
      inputs: Keyword.get(opts, :inputs, new_schema()),
      outputs: Keyword.get(opts, :outputs, new_schema()),
      tags: Keyword.get(opts, :tags, []),
      average_response_size: Keyword.get(opts, :average_response_size, nil),
      provider: Keyword.fetch!(opts, :provider)
    }
  end

  @doc """
  Validates a tool definition.
  """
  @spec validate_tool(T.tool()) :: :ok | {:error, String.t()}
  def validate_tool(tool) do
    cond do
      is_nil(tool.name) or tool.name == "" ->
        {:error, "Tool name is required"}

      is_nil(tool.provider) ->
        {:error, "Tool provider is required"}

      true ->
        :ok
    end
  end

  @doc """
  Checks if a tool matches a search query.
  """
  @spec matches_query?(T.tool(), String.t()) :: boolean()
  def matches_query?(_tool, query) when query == "" or is_nil(query), do: true

  def matches_query?(tool, query) do
    query_lower = String.downcase(query)

    String.downcase(tool.name) |> String.contains?(query_lower) or
      String.downcase(tool.description) |> String.contains?(query_lower) or
      Enum.any?(tool.tags, &(String.downcase(&1) |> String.contains?(query_lower)))
  end

  @doc """
  Normalizes tool name by ensuring it has a provider prefix.
  """
  @spec normalize_name(String.t(), String.t()) :: String.t()
  def normalize_name(tool_name, provider_name) do
    case String.split(tool_name, ".", parts: 2) do
      [^provider_name, _suffix] -> tool_name
      [suffix] -> "#{provider_name}.#{suffix}"
      [prefix, suffix] when prefix != provider_name -> "#{provider_name}.#{suffix}"
    end
  end

  @doc """
  Extracts the tool name without provider prefix.
  """
  @spec extract_tool_name(String.t()) :: String.t()
  def extract_tool_name(full_name) do
    case String.split(full_name, ".", parts: 2) do
      [_provider, tool_name] -> tool_name
      [tool_name] -> tool_name
    end
  end

  @doc """
  Extracts the provider name from a full tool name.
  """
  @spec extract_provider_name(String.t()) :: String.t()
  def extract_provider_name(full_name) do
    case String.split(full_name, ".", parts: 2) do
      [provider_name, _tool] -> provider_name
      [_tool] -> ""
    end
  end
end
