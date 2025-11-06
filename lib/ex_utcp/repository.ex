defmodule ExUtcp.Repository do
  @moduledoc """
  In-memory repository for storing providers and tools.

  This module provides a simple in-memory storage solution for UTCP providers and tools.
  In a production environment, you might want to implement a persistent storage backend.
  """

  alias ExUtcp.Types, as: T

  @doc """
  Creates a new in-memory tool repository.
  """
  @spec new() :: T.tool_repository()
  def new do
    %{
      tools: %{},
      providers: %{}
    }
  end

  @doc """
  Saves a provider with its associated tools.
  """
  @spec save_provider_with_tools(T.tool_repository(), T.provider(), [T.tool()]) ::
          T.tool_repository()
  def save_provider_with_tools(repo, provider, tools) do
    provider_name = ExUtcp.Providers.get_name(provider)

    repo
    |> Map.put(:providers, Map.put(repo.providers, provider_name, provider))
    |> Map.put(:tools, Map.put(repo.tools, provider_name, tools))
  end

  @doc """
  Gets a provider by name.
  """
  @spec get_provider(T.tool_repository(), String.t()) :: T.provider() | nil
  def get_provider(repo, provider_name) do
    Map.get(repo.providers, provider_name)
  end

  @doc """
  Gets all providers.
  """
  @spec get_providers(T.tool_repository()) :: [T.provider()]
  def get_providers(repo) do
    Map.values(repo.providers)
  end

  @doc """
  Adds a tool to the repository.
  """
  @spec add_tool(T.tool_repository(), T.tool()) ::
          {:ok, T.tool_repository()} | {:error, String.t()}
  def add_tool(repo, tool) do
    provider_name = tool.provider_name

    # Check if provider exists
    case Map.get(repo.providers, provider_name) do
      nil ->
        {:error, "Provider #{provider_name} not found"}

      _provider ->
        # Add tool to the provider's tools
        existing_tools = Map.get(repo.tools, provider_name, [])
        updated_tools = [tool | existing_tools]
        new_repo = Map.put(repo, :tools, Map.put(repo.tools, provider_name, updated_tools))
        {:ok, new_repo}
    end
  end

  @doc """
  Gets a tool by name.
  """
  @spec get_tool(T.tool_repository(), String.t()) :: T.tool() | nil
  def get_tool(repo, tool_name) do
    repo.tools
    |> Map.values()
    |> List.flatten()
    |> Enum.find(&(&1.name == tool_name))
  end

  @doc """
  Gets all tools.
  """
  @spec get_tools(T.tool_repository()) :: [T.tool()]
  def get_tools(repo) do
    Map.values(repo.tools) |> List.flatten()
  end

  @doc """
  Gets tools by provider name.
  """
  @spec get_tools_by_provider(T.tool_repository(), String.t()) :: [T.tool()]
  def get_tools_by_provider(repo, provider_name) do
    Map.get(repo.tools, provider_name, [])
  end

  @doc """
  Removes a provider and its tools.
  """
  @spec remove_provider(T.tool_repository(), String.t()) :: T.tool_repository()
  def remove_provider(repo, provider_name) do
    repo
    |> Map.put(:providers, Map.delete(repo.providers, provider_name))
    |> Map.put(:tools, Map.delete(repo.tools, provider_name))
  end

  @doc """
  Removes a specific tool.
  """
  @spec remove_tool(T.tool_repository(), String.t()) :: T.tool_repository()
  def remove_tool(repo, tool_name) do
    updated_tools =
      repo.tools
      |> Map.new(fn {provider_name, tools} ->
        filtered_tools = Enum.reject(tools, &(&1.name == tool_name))
        {provider_name, filtered_tools}
      end)

    Map.put(repo, :tools, updated_tools)
  end

  @doc """
  Searches for tools matching a query.
  """
  @spec search_tools(T.tool_repository(), String.t(), integer()) :: [T.tool()]
  def search_tools(repo, query, limit) do
    repo
    |> get_tools()
    |> Enum.filter(&ExUtcp.Tools.matches_query?(&1, query))
    |> Enum.take(limit)
  end

  @doc """
  Gets the count of tools in the repository.
  """
  @spec tool_count(T.tool_repository()) :: integer()
  def tool_count(repo) do
    repo.tools
    |> Map.values()
    |> List.flatten()
    |> length()
  end

  @doc """
  Gets the count of providers in the repository.
  """
  @spec provider_count(T.tool_repository()) :: integer()
  def provider_count(repo) do
    map_size(repo.providers)
  end

  @doc """
  Checks if a provider exists.
  """
  @spec has_provider?(T.tool_repository(), String.t()) :: boolean()
  def has_provider?(repo, provider_name) do
    Map.has_key?(repo.providers, provider_name)
  end

  @doc """
  Checks if a tool exists.
  """
  @spec has_tool?(T.tool_repository(), String.t()) :: boolean()
  def has_tool?(repo, tool_name) do
    get_tool(repo, tool_name) != nil
  end

  @doc """
  Clears all providers and tools from the repository.
  """
  @spec clear(T.tool_repository()) :: T.tool_repository()
  def clear(_repo) do
    new()
  end
end
