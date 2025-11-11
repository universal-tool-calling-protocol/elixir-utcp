defmodule ExUtcp.Search do
  @moduledoc """
  Advanced search functionality for UTCP tools and providers.

  Provides multiple search algorithms including:
  - Exact matching
  - Fuzzy search with similarity scoring
  - Semantic search based on descriptions
  - Tag-based filtering
  - Provider-based filtering
  - Transport-based filtering
  """

  alias ExUtcp.Search.Engine
  alias ExUtcp.Search.Filters
  alias ExUtcp.Search.Fuzzy
  alias ExUtcp.Search.Ranking
  alias ExUtcp.Search.Security
  alias ExUtcp.Search.Semantic
  alias ExUtcp.Types

  @type search_options :: %{
          algorithm: :exact | :fuzzy | :semantic | :combined,
          filters: %{
            providers: [String.t()],
            transports: [atom()],
            tags: [String.t()]
          },
          limit: integer(),
          threshold: float(),
          include_descriptions: boolean(),
          use_haystack: boolean(),
          security_scan: boolean(),
          filter_sensitive: boolean()
        }

  @type search_result :: %{
          tool: Types.tool(),
          score: float(),
          match_type: :exact | :fuzzy | :semantic,
          matched_fields: [String.t()],
          security_warnings: [map()]
        }

  @doc """
  Creates a new search engine with default configuration.
  """
  @spec new(keyword()) :: Engine.t()
  def new(opts \\ []) do
    Engine.new(opts)
  end

  @doc """
  Searches for tools using the specified query and options.
  """
  @spec search_tools(Engine.t(), String.t(), search_options()) :: [search_result()]
  def search_tools(engine, query, opts \\ %{}) do
    opts = merge_default_options(opts)

    tools = Engine.get_all_tools(engine)

    # Apply filters first to reduce search space
    filtered_tools = Filters.apply_filters(tools, opts.filters)

    # Apply search algorithm
    results =
      case opts.algorithm do
        :exact -> search_exact(filtered_tools, query, opts)
        :fuzzy -> search_fuzzy(filtered_tools, query, opts)
        :semantic -> search_semantic(filtered_tools, query, opts)
        :combined -> search_combined(filtered_tools, query, opts)
      end

    # Rank and limit results
    ranked_results =
      results
      |> Ranking.rank_results(query, opts)
      |> Enum.take(opts.limit)

    # Apply security scanning if requested
    if Map.get(opts, :security_scan, false) do
      ranked_results = Security.add_security_warnings(ranked_results)

      if Map.get(opts, :filter_sensitive, false) do
        Security.filter_secure_results(ranked_results)
      else
        ranked_results
      end
    else
      # Add empty security warnings for consistency
      Enum.map(ranked_results, &Map.put(&1, :security_warnings, []))
    end
  end

  @doc """
  Searches for providers using the specified query and options.
  """
  @spec search_providers(Engine.t(), String.t(), search_options()) :: [map()]
  def search_providers(engine, query, opts \\ %{}) do
    opts = merge_default_options(opts)

    providers = Engine.get_all_providers(engine)

    # Apply filters
    filtered_providers = Filters.apply_provider_filters(providers, opts.filters)

    # Apply search algorithm
    results =
      case opts.algorithm do
        :exact -> search_providers_exact(filtered_providers, query, opts)
        :fuzzy -> search_providers_fuzzy(filtered_providers, query, opts)
        :semantic -> search_providers_semantic(filtered_providers, query, opts)
        :combined -> search_providers_combined(filtered_providers, query, opts)
      end

    # Rank and limit results
    results
    |> Ranking.rank_provider_results(query, opts)
    |> Enum.take(opts.limit)
  end

  @doc """
  Suggests similar tools based on a given tool.
  """
  @spec suggest_similar_tools(Engine.t(), Types.tool(), keyword()) :: [search_result()]
  def suggest_similar_tools(engine, tool, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.3)

    all_tools =
      Engine.get_all_tools(engine)
      |> Enum.reject(&(&1.name == tool.name))

    # Use semantic similarity based on descriptions and tags
    Semantic.find_similar_tools(tool, all_tools, threshold)
    |> Enum.take(limit)
  end

  @doc """
  Gets search suggestions based on partial query.
  """
  @spec get_suggestions(Engine.t(), String.t(), keyword()) :: [String.t()]
  def get_suggestions(engine, partial_query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    min_length = Keyword.get(opts, :min_length, 2)

    if String.length(partial_query) < min_length do
      []
    else
      tools = Engine.get_all_tools(engine)
      providers = Engine.get_all_providers(engine)

      # Get suggestions from tool names, descriptions, and provider names
      tool_suggestions =
        Enum.flat_map(tools, fn tool ->
          [tool.name | extract_keywords(tool.definition.description)]
        end)

      provider_suggestions = Enum.map(providers, & &1.name)

      all_suggestions = tool_suggestions ++ provider_suggestions

      all_suggestions
      |> Enum.filter(&String.contains?(String.downcase(&1), String.downcase(partial_query)))
      |> Enum.uniq()
      |> Enum.take(limit)
    end
  end

  # Private functions

  defp merge_default_options(opts) do
    defaults = %{
      algorithm: :combined,
      filters: %{
        providers: [],
        transports: [],
        tags: []
      },
      limit: 20,
      threshold: 0.1,
      include_descriptions: true,
      use_haystack: true,
      security_scan: false,
      filter_sensitive: false
    }

    Map.merge(defaults, opts)
  end

  defp search_exact(tools, query, opts) do
    query_lower = String.downcase(query)

    Enum.filter(tools, fn tool ->
      name_match = String.downcase(tool.name) == query_lower

      desc_match =
        opts.include_descriptions and
          String.contains?(String.downcase(tool.definition.description), query_lower)

      name_match or desc_match
    end)
    |> Enum.map(fn tool ->
      match_type = if String.downcase(tool.name) == query_lower, do: :exact, else: :exact
      matched_fields = get_matched_fields(tool, query, :exact)

      %{
        tool: tool,
        score: 1.0,
        match_type: match_type,
        matched_fields: matched_fields
      }
    end)
  end

  defp search_fuzzy(tools, query, opts) do
    # Use enhanced fuzzy search with FuzzyCompare
    threshold = Map.get(opts, :threshold, 0.6)

    tools
    |> Enum.map(fn tool ->
      name_similarity = Fuzzy.best_similarity(tool.name, query)

      desc_similarity =
        if opts.include_descriptions do
          Fuzzy.best_similarity(tool.definition.description, query)
        else
          0.0
        end

      max_similarity = max(name_similarity, desc_similarity)

      if max_similarity >= threshold do
        matched_fields = []

        matched_fields =
          if name_similarity >= threshold, do: ["name" | matched_fields], else: matched_fields

        matched_fields =
          if desc_similarity >= threshold,
            do: ["description" | matched_fields],
            else: matched_fields

        %{
          tool: tool,
          score: max_similarity,
          match_type: :fuzzy,
          matched_fields: matched_fields
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp search_semantic(tools, query, opts) do
    Semantic.search_tools(tools, query, opts)
  end

  defp search_combined(tools, query, opts) do
    # Combine exact, fuzzy, and semantic search results
    exact_results = search_exact(tools, query, opts)
    fuzzy_results = search_fuzzy(tools, query, opts)
    semantic_results = search_semantic(tools, query, opts)

    # Merge and deduplicate results
    all_results = exact_results ++ fuzzy_results ++ semantic_results

    all_results
    |> Enum.group_by(& &1.tool.name)
    |> Enum.map(fn {_name, results} ->
      # Take the best result for each tool
      Enum.max_by(results, & &1.score)
    end)
  end

  defp search_providers_exact(providers, query, _opts) do
    query_lower = String.downcase(query)

    Enum.filter(providers, fn provider ->
      String.downcase(provider.name) == query_lower or
        Atom.to_string(provider.type) == query_lower
    end)
    |> Enum.map(fn provider ->
      %{
        provider: provider,
        score: 1.0,
        match_type: :exact,
        matched_fields: ["name"]
      }
    end)
  end

  defp search_providers_fuzzy(providers, query, opts) do
    Fuzzy.search_providers(providers, query, opts)
  end

  defp search_providers_semantic(providers, query, opts) do
    Semantic.search_providers(providers, query, opts)
  end

  defp search_providers_combined(providers, query, opts) do
    # Combine exact, fuzzy, and semantic search results for providers
    exact_results = search_providers_exact(providers, query, opts)
    fuzzy_results = search_providers_fuzzy(providers, query, opts)
    semantic_results = search_providers_semantic(providers, query, opts)

    # Merge and deduplicate results
    all_results = exact_results ++ fuzzy_results ++ semantic_results

    all_results
    |> Enum.group_by(& &1.provider.name)
    |> Enum.map(fn {_name, results} ->
      # Take the best result for each provider
      Enum.max_by(results, & &1.score)
    end)
  end

  defp get_matched_fields(tool, query, match_type) do
    query_lower = String.downcase(query)
    fields = []

    fields =
      if String.contains?(String.downcase(tool.name), query_lower) do
        ["name" | fields]
      else
        fields
      end

    fields =
      if String.contains?(String.downcase(tool.definition.description), query_lower) do
        ["description" | fields]
      else
        fields
      end

    case match_type do
      :exact -> fields
      _ -> fields
    end
  end

  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\w]+/, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.uniq()
  end
end
