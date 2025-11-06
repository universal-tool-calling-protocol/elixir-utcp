defmodule ExUtcp.Search.Fuzzy do
  @moduledoc """
  Fuzzy search implementation for UTCP tools and providers.

  Uses FuzzyCompare library for advanced string similarity algorithms.
  """

  alias FuzzyCompare

  @doc """
  Searches tools using fuzzy matching.
  """
  @spec search_tools(list(), String.t(), map()) :: list()
  def search_tools(tools, query, opts) do
    threshold = Map.get(opts, :threshold, 0.6)

    tools
    |> Enum.map(fn tool ->
      name_similarity = string_similarity(tool.name, query)

      desc_similarity =
        if opts.include_descriptions do
          string_similarity(tool.definition.description, query)
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

  @doc """
  Searches providers using fuzzy matching.
  """
  @spec search_providers(list(), String.t(), map()) :: list()
  def search_providers(providers, query, opts) do
    threshold = Map.get(opts, :threshold, 0.6)

    providers
    |> Enum.map(fn provider ->
      name_similarity = string_similarity(provider.name, query)
      type_similarity = string_similarity(Atom.to_string(provider.type), query)

      max_similarity = max(name_similarity, type_similarity)

      if max_similarity >= threshold do
        matched_fields = []

        matched_fields =
          if name_similarity >= threshold, do: ["name" | matched_fields], else: matched_fields

        matched_fields =
          if type_similarity >= threshold, do: ["type" | matched_fields], else: matched_fields

        %{
          provider: provider,
          score: max_similarity,
          match_type: :fuzzy,
          matched_fields: matched_fields
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Calculates string similarity using FuzzyCompare algorithms.
  """
  @spec string_similarity(String.t(), String.t()) :: float()
  def string_similarity(str1, str2) do
    str1_lower = String.downcase(str1)
    str2_lower = String.downcase(str2)

    cond do
      str1_lower == str2_lower ->
        1.0

      String.contains?(str1_lower, str2_lower) ->
        0.8

      String.contains?(str2_lower, str1_lower) ->
        0.8

      true ->
        # Use FuzzyCompare for advanced similarity calculation
        case FuzzyCompare.similarity(str1_lower, str2_lower) do
          {:ok, similarity} -> similarity
          _ -> levenshtein_similarity(str1_lower, str2_lower)
        end
    end
  end

  @doc """
  Calculates multiple similarity metrics and returns the best score using FuzzyCompare.
  """
  @spec best_similarity(String.t(), String.t()) :: float()
  def best_similarity(str1, str2) do
    # Use FuzzyCompare's main similarity function
    FuzzyCompare.similarity(str1, str2)
  end

  @doc """
  Calculates Levenshtein distance (fallback implementation).
  """
  @spec levenshtein_distance(String.t(), String.t()) :: integer()
  def levenshtein_distance(str1, str2) do
    # Simple Levenshtein implementation as fallback
    str1_chars = String.graphemes(str1)
    str2_chars = String.graphemes(str2)

    levenshtein_distance_impl(str1_chars, str2_chars)
  end

  @doc """
  Calculates similarity score based on Levenshtein distance.
  """
  @spec levenshtein_similarity(String.t(), String.t()) :: float()
  def levenshtein_similarity(str1, str2) do
    max_length = max(String.length(str1), String.length(str2))

    if max_length == 0 do
      1.0
    else
      distance = levenshtein_distance(str1, str2)
      1.0 - distance / max_length
    end
  end

  # Private functions

  defp levenshtein_distance_impl(str1_chars, str2_chars) do
    len1 = length(str1_chars)
    len2 = length(str2_chars)

    # Initialize distance matrix
    matrix =
      for i <- 0..len1, into: %{} do
        {i, %{0 => i}}
      end

    matrix =
      for j <- 0..len2, reduce: matrix do
        acc -> put_in(acc, [0, j], j)
      end

    # Fill the matrix
    matrix =
      for i <- 1..len1, j <- 1..len2, reduce: matrix do
        acc ->
          char1 = Enum.at(str1_chars, i - 1)
          char2 = Enum.at(str2_chars, j - 1)

          cost = if char1 == char2, do: 0, else: 1

          min_val =
            min(
              # deletion
              acc[i - 1][j] + 1,
              min(
                # insertion
                acc[i][j - 1] + 1,
                # substitution
                acc[i - 1][j - 1] + cost
              )
            )

          put_in(acc, [i, j], min_val)
      end

    matrix[len1][len2]
  end
end
