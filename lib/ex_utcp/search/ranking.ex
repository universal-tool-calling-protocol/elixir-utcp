defmodule ExUtcp.Search.Ranking do
  @moduledoc """
  Search result ranking and scoring for UTCP tools and providers.

  Provides sophisticated ranking algorithms to order search results by relevance.
  """

  @doc """
  Ranks search results based on relevance and query context.
  """
  @spec rank_results([map()], String.t(), map()) :: [map()]
  def rank_results(results, query, opts) do
    results
    |> Enum.map(&calculate_final_score(&1, query, opts))
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Ranks provider search results.
  """
  @spec rank_provider_results([map()], String.t(), map()) :: [map()]
  def rank_provider_results(results, query, opts) do
    results
    |> Enum.map(&calculate_provider_final_score(&1, query, opts))
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Calculates popularity score based on usage patterns.
  """
  @spec popularity_score(map()) :: float()
  def popularity_score(result) do
    # In a real implementation, this would be based on actual usage statistics
    # For now, we'll use simple heuristics

    base_score = 0.5

    # Get name from either tool or provider
    name_lower =
      case result do
        %{tool: tool} -> String.downcase(tool.name || "")
        %{provider: provider} -> String.downcase(provider.name || "")
        _ -> ""
      end

    cond do
      String.contains?(name_lower, ["get", "list", "fetch", "retrieve"]) -> base_score + 0.3
      String.contains?(name_lower, ["create", "post", "add", "insert"]) -> base_score + 0.2
      String.contains?(name_lower, ["update", "put", "modify", "edit"]) -> base_score + 0.2
      String.contains?(name_lower, ["delete", "remove", "destroy"]) -> base_score + 0.1
      true -> base_score
    end
  end

  @doc """
  Calculates recency score based on when the tool was last used or updated.
  """
  @spec recency_score(map()) :: float()
  def recency_score(_result) do
    # In a real implementation, this would be based on actual timestamps
    # For now, return a neutral score
    0.5
  end

  @doc """
  Calculates quality score based on tool definition completeness.
  """
  @spec quality_score(map()) :: float()
  def quality_score(%{tool: tool}) do
    base_score = 0.5

    # Check for description quality
    desc_score =
      if String.length(tool.definition.description) > 50 do
        0.2
      else
        0.0
      end

    # Check for parameter documentation
    param_score =
      case tool.definition do
        %{parameters: %{"properties" => properties}} ->
          documented_params =
            properties
            |> Enum.count(fn {_name, param_def} ->
              Map.has_key?(param_def, "description") and
                String.length(param_def["description"]) > 10
            end)

          total_params = map_size(properties)
          if total_params > 0, do: documented_params / total_params * 0.2, else: 0.0

        _ ->
          0.0
      end

    # Check for response documentation
    response_score =
      case tool.definition do
        %{response: %{"properties" => properties}} ->
          documented_responses =
            properties
            |> Enum.count(fn {_name, field_def} ->
              Map.has_key?(field_def, "description") and
                String.length(field_def["description"]) > 10
            end)

          total_responses = map_size(properties)
          if total_responses > 0, do: documented_responses / total_responses * 0.1, else: 0.0

        _ ->
          0.0
      end

    base_score + desc_score + param_score + response_score
  end

  def quality_score(%{provider: _provider}) do
    # Provider quality score based on configuration completeness
    0.5
  end

  def quality_score(_), do: 0.5

  @doc """
  Calculates context relevance score based on query context.
  """
  @spec context_relevance_score(map(), String.t()) :: float()
  def context_relevance_score(result, query) do
    query_lower = String.downcase(query)

    # Boost score for exact matches in important fields
    exact_name_match =
      case result do
        %{tool: tool} -> String.downcase(tool.name) == query_lower
        %{provider: provider} -> String.downcase(provider.name) == query_lower
        _ -> false
      end

    if exact_name_match do
      1.0
    else
      # Calculate based on matched fields
      matched_fields = Map.get(result, :matched_fields, [])

      cond do
        "name" in matched_fields -> 0.8
        "description" in matched_fields -> 0.6
        "type" in matched_fields -> 0.4
        true -> 0.2
      end
    end
  end

  @doc """
  Applies boost factors based on search preferences.
  """
  @spec apply_boost_factors(map(), map()) :: map()
  def apply_boost_factors(result, opts) do
    boost_factors = Map.get(opts, :boost_factors, %{})

    # Apply transport-specific boosts
    transport_boost =
      case result do
        %{tool: tool} ->
          transport = infer_transport_from_tool(tool)
          Map.get(boost_factors, transport, 1.0)

        %{provider: provider} ->
          Map.get(boost_factors, provider.type, 1.0)

        _ ->
          1.0
      end

    # Apply match type boosts
    match_type_boost =
      case result.match_type do
        :exact -> Map.get(boost_factors, :exact_match, 1.2)
        :fuzzy -> Map.get(boost_factors, :fuzzy_match, 1.0)
        :semantic -> Map.get(boost_factors, :semantic_match, 0.9)
      end

    boosted_score = result.score * transport_boost * match_type_boost
    %{result | score: boosted_score}
  end

  # Private functions

  defp calculate_final_score(result, query, opts) do
    # Combine multiple scoring factors
    base_score = result.score
    popularity = popularity_score(result)
    recency = recency_score(result)
    quality = quality_score(result)
    context_relevance = context_relevance_score(result, query)

    # Weighted combination
    weights = %{
      base: 0.4,
      popularity: 0.2,
      recency: 0.1,
      quality: 0.2,
      context: 0.1
    }

    final_score =
      base_score * weights.base +
        popularity * weights.popularity +
        recency * weights.recency +
        quality * weights.quality +
        context_relevance * weights.context

    result = %{result | score: final_score}

    # Apply boost factors
    apply_boost_factors(result, opts)
  end

  defp calculate_provider_final_score(result, query, opts) do
    # Simpler scoring for providers
    base_score = result.score
    popularity = popularity_score(result)
    context_relevance = context_relevance_score(result, query)

    # Weighted combination
    final_score = base_score * 0.6 + popularity * 0.2 + context_relevance * 0.2

    result = %{result | score: final_score}

    # Apply boost factors
    apply_boost_factors(result, opts)
  end

  defp infer_transport_from_tool(tool) do
    # Infer transport type from provider name
    provider_name_lower = String.downcase(tool.provider_name)

    cond do
      String.contains?(provider_name_lower, "http") -> :http
      String.contains?(provider_name_lower, "websocket") -> :websocket
      String.contains?(provider_name_lower, "grpc") -> :grpc
      String.contains?(provider_name_lower, "graphql") -> :graphql
      String.contains?(provider_name_lower, "mcp") -> :mcp
      String.contains?(provider_name_lower, "tcp") -> :tcp
      String.contains?(provider_name_lower, "udp") -> :udp
      String.contains?(provider_name_lower, "cli") -> :cli
      true -> :unknown
    end
  end
end
