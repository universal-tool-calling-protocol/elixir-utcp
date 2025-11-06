defmodule ExUtcp.Search.Semantic do
  @moduledoc """
  Semantic search implementation for UTCP tools and providers.

  Uses Haystack for full-text search and keyword extraction for intelligent tool discovery.
  """

  alias ExUtcp.Types

  @doc """
  Creates a Haystack index from tools for full-text search.
  """
  @spec create_tools_index([Types.tool()]) :: Haystack.t()
  def create_tools_index(tools) do
    # Create Haystack index with tool documents
    documents =
      Enum.map(tools, fn tool ->
        %{
          id: tool.name,
          title: tool.name,
          content: tool.definition.description,
          provider_name: tool.provider_name,
          parameters: Jason.encode!(tool.definition.parameters || %{}),
          response: Jason.encode!(tool.definition.response || %{})
        }
      end)

    # Create Haystack index with documents
    Haystack.new(documents)
  end

  @doc """
  Searches tools using Haystack full-text search and semantic matching.
  """
  @spec search_tools(list(), String.t(), map()) :: list()
  def search_tools(tools, query, opts) do
    use_haystack = Map.get(opts, :use_haystack, true)

    if use_haystack and length(tools) > 10 do
      # Use Haystack for large tool sets
      search_tools_with_haystack(tools, query, opts)
    else
      # Use keyword-based semantic search for smaller sets
      search_tools_with_keywords(tools, query, opts)
    end
  end

  @doc """
  Searches tools using Haystack full-text search.
  """
  @spec search_tools_with_haystack([Types.tool()], String.t(), map()) :: list()
  def search_tools_with_haystack(tools, query, opts) do
    threshold = Map.get(opts, :threshold, 0.3)
    limit = Map.get(opts, :limit, 20)

    try do
      # Create Haystack index
      index = create_tools_index(tools)

      # Perform search using Haystack.index/3
      results = Haystack.index(index, query, limit)

      results
      |> Enum.take(limit)
      |> Enum.map(fn result ->
        # Find the original tool by ID
        tool = Enum.find(tools, &(&1.name == result.id))

        if tool and result.score >= threshold do
          %{
            tool: tool,
            score: result.score,
            match_type: :semantic,
            matched_fields: ["content", "title"]
          }
        end
      end)
      |> Enum.reject(&is_nil/1)
    rescue
      _ ->
        # Fallback to keyword-based search if Haystack fails
        search_tools_with_keywords(tools, query, opts)
    end
  end

  @doc """
  Searches tools using keyword-based semantic matching.
  """
  @spec search_tools_with_keywords([Types.tool()], String.t(), map()) :: list()
  def search_tools_with_keywords(tools, query, opts) do
    threshold = Map.get(opts, :threshold, 0.3)
    query_keywords = extract_keywords(query)

    tools
    |> Enum.map(fn tool ->
      score = calculate_semantic_score(tool, query_keywords, opts)

      if score >= threshold do
        %{
          tool: tool,
          score: score,
          match_type: :semantic,
          matched_fields: get_semantic_matched_fields(tool, query_keywords)
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Searches providers using semantic matching.
  """
  @spec search_providers(list(), String.t(), map()) :: list()
  def search_providers(providers, query, opts) do
    threshold = Map.get(opts, :threshold, 0.3)
    query_keywords = extract_keywords(query)

    providers
    |> Enum.map(fn provider ->
      score = calculate_provider_semantic_score(provider, query_keywords)

      if score >= threshold do
        %{
          provider: provider,
          score: score,
          match_type: :semantic,
          matched_fields: get_provider_semantic_matched_fields(provider, query_keywords)
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Finds similar tools based on semantic similarity.
  """
  @spec find_similar_tools(Types.tool(), [Types.tool()], float()) :: list()
  def find_similar_tools(reference_tool, candidate_tools, threshold \\ 0.3) do
    reference_keywords = extract_keywords(reference_tool.definition.description)

    candidate_tools
    |> Enum.map(fn tool ->
      score = calculate_tool_similarity(reference_tool, tool, reference_keywords)

      if score >= threshold do
        %{
          tool: tool,
          score: score,
          match_type: :semantic,
          matched_fields: ["description", "name"]
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Extracts keywords from text for semantic analysis.
  """
  @spec extract_keywords(String.t()) :: [String.t()]
  def extract_keywords(text) do
    # Common stop words to filter out
    stop_words =
      MapSet.new([
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "by",
        "for",
        "from",
        "has",
        "he",
        "in",
        "is",
        "it",
        "its",
        "of",
        "on",
        "that",
        "the",
        "to",
        "was",
        "will",
        "with",
        "or",
        "but",
        "not",
        "this",
        "can",
        "have",
        "do",
        "does",
        "get",
        "set",
        "use",
        "using",
        "used"
      ])

    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> Enum.uniq()
  end

  @doc """
  Calculates semantic similarity between two sets of keywords.
  """
  @spec keyword_similarity([String.t()], [String.t()]) :: float()
  def keyword_similarity(keywords1, keywords2) do
    if Enum.empty?(keywords1) or Enum.empty?(keywords2) do
      0.0
    else
      set1 = MapSet.new(keywords1)
      set2 = MapSet.new(keywords2)

      intersection_size = MapSet.intersection(set1, set2) |> MapSet.size()
      union_size = MapSet.union(set1, set2) |> MapSet.size()

      if union_size == 0 do
        0.0
      else
        intersection_size / union_size
      end
    end
  end

  @doc """
  Calculates contextual similarity based on tool categories and domains.
  """
  @spec contextual_similarity(Types.tool(), [String.t()]) :: float()
  def contextual_similarity(tool, query_keywords) do
    # Extract domain-specific keywords from tool definition
    tool_context = extract_tool_context(tool)

    # Calculate similarity with query context
    keyword_similarity(tool_context, query_keywords)
  end

  # Private functions

  defp calculate_semantic_score(tool, query_keywords, opts) do
    # Extract keywords from tool name and description
    name_keywords = extract_keywords(tool.name)

    desc_keywords =
      if Map.get(opts, :include_descriptions, true) do
        extract_keywords(tool.definition.description)
      else
        []
      end

    # Calculate different types of similarity
    contextual_sim = contextual_similarity(tool, query_keywords)

    # Weighted combination
    name_weight = 0.4
    desc_weight = 0.4
    context_weight = 0.2

    name_sim = keyword_similarity(name_keywords, query_keywords)
    desc_sim = keyword_similarity(desc_keywords, query_keywords)

    name_sim * name_weight + desc_sim * desc_weight + contextual_sim * context_weight
  end

  defp calculate_provider_semantic_score(provider, query_keywords) do
    # Extract keywords from provider name and type
    name_keywords = extract_keywords(provider.name)
    type_keywords = [Atom.to_string(provider.type)]

    all_provider_keywords = name_keywords ++ type_keywords

    keyword_similarity(all_provider_keywords, query_keywords)
  end

  defp calculate_tool_similarity(tool1, tool2, reference_keywords) do
    tool2_keywords = extract_keywords(tool2.definition.description)

    # Calculate similarity between descriptions
    desc_similarity = keyword_similarity(reference_keywords, tool2_keywords)

    # Calculate name similarity
    name_similarity =
      keyword_similarity(
        extract_keywords(tool1.name),
        extract_keywords(tool2.name)
      )

    # Weighted combination
    desc_similarity * 0.7 + name_similarity * 0.3
  end

  defp get_semantic_matched_fields(tool, query_keywords) do
    fields = []

    name_keywords = extract_keywords(tool.name)
    desc_keywords = extract_keywords(tool.definition.description)

    fields =
      if keyword_similarity(name_keywords, query_keywords) > 0.1 do
        ["name" | fields]
      else
        fields
      end

    fields =
      if keyword_similarity(desc_keywords, query_keywords) > 0.1 do
        ["description" | fields]
      else
        fields
      end

    fields
  end

  defp get_provider_semantic_matched_fields(provider, query_keywords) do
    fields = []

    name_keywords = extract_keywords(provider.name)
    type_keywords = [Atom.to_string(provider.type)]

    fields =
      if keyword_similarity(name_keywords, query_keywords) > 0.1 do
        ["name" | fields]
      else
        fields
      end

    fields =
      if keyword_similarity(type_keywords, query_keywords) > 0.1 do
        ["type" | fields]
      else
        fields
      end

    fields
  end

  defp extract_tool_context(tool) do
    # Extract contextual keywords from tool definition
    context_keywords = []

    # Add keywords from parameters
    context_keywords =
      if Map.has_key?(tool.definition, :parameters) do
        param_keywords = extract_parameter_keywords(tool.definition.parameters)
        context_keywords ++ param_keywords
      else
        context_keywords
      end

    # Add keywords from response schema
    context_keywords =
      if Map.has_key?(tool.definition, :response) do
        response_keywords = extract_response_keywords(tool.definition.response)
        context_keywords ++ response_keywords
      else
        context_keywords
      end

    context_keywords
  end

  defp extract_parameter_keywords(parameters) when is_map(parameters) do
    # Extract keywords from parameter names and descriptions
    parameters
    |> Map.get("properties", %{})
    |> Enum.flat_map(fn {param_name, param_def} ->
      name_keywords = extract_keywords(param_name)

      desc_keywords =
        case param_def do
          %{"description" => desc} -> extract_keywords(desc)
          _ -> []
        end

      name_keywords ++ desc_keywords
    end)
  end

  defp extract_parameter_keywords(_), do: []

  defp extract_response_keywords(response) when is_map(response) do
    # Extract keywords from response schema
    response
    |> Map.get("properties", %{})
    |> Enum.flat_map(fn {field_name, field_def} ->
      name_keywords = extract_keywords(field_name)

      desc_keywords =
        case field_def do
          %{"description" => desc} -> extract_keywords(desc)
          _ -> []
        end

      name_keywords ++ desc_keywords
    end)
  end

  defp extract_response_keywords(_), do: []
end
