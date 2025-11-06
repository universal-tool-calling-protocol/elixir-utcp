defmodule ExUtcp.Transports.Graphql.Schema do
  @moduledoc """
  GraphQL schema introspection and tool extraction utilities.
  """

  require Logger

  @doc """
  Extracts tools from a GraphQL schema introspection result.
  """
  @spec extract_tools(map()) :: [map()]
  def extract_tools(schema) do
    tools = []

    # Extract query tools
    query_tools = extract_operation_tools(schema, "query", "Query")
    tools = tools ++ query_tools

    # Extract mutation tools
    mutation_tools = extract_operation_tools(schema, "mutation", "Mutation")
    tools = tools ++ mutation_tools

    # Extract subscription tools
    subscription_tools = extract_operation_tools(schema, "subscription", "Subscription")
    tools = tools ++ subscription_tools

    tools
  rescue
    error ->
      Logger.error("Failed to extract tools from GraphQL schema: #{inspect(error)}")
      []
  end

  @doc """
  Validates a GraphQL query string.
  """
  @spec validate_query(String.t()) :: {:ok, String.t()} | {:error, term()}
  def validate_query(query_string) do
    # Basic validation - check for common GraphQL syntax
    trimmed = String.trim(query_string)

    cond do
      String.length(trimmed) == 0 ->
        {:error, "Empty query"}

      not String.contains?(trimmed, ["query", "mutation", "subscription"]) ->
        {:error, "Query must contain query, mutation, or subscription"}

      not String.contains?(trimmed, "{") ->
        {:error, "Query must contain selection set"}

      true ->
        {:ok, trimmed}
    end
  rescue
    error ->
      {:error, "Query validation failed: #{inspect(error)}"}
  end

  @doc """
  Builds a GraphQL query from tool name and arguments.
  """
  @spec build_query(String.t(), map()) :: String.t()
  def build_query(tool_name, args) do
    operation_name = String.replace(tool_name, ".", "_")
    args_string = build_args_string(args)

    """
    query #{operation_name}(#{args_string}) {
      #{operation_name}(#{args_string}) {
        result
        success
        error
      }
    }
    """
  end

  @doc """
  Builds a GraphQL mutation from tool name and arguments.
  """
  @spec build_mutation(String.t(), map()) :: String.t()
  def build_mutation(tool_name, args) do
    operation_name = String.replace(tool_name, ".", "_")
    args_string = build_args_string(args)

    """
    mutation #{operation_name}(#{args_string}) {
      #{operation_name}(#{args_string}) {
        result
        success
        error
      }
    }
    """
  end

  @doc """
  Builds a GraphQL subscription from tool name and arguments.
  """
  @spec build_subscription(String.t(), map()) :: String.t()
  def build_subscription(tool_name, args) do
    operation_name = String.replace(tool_name, ".", "_")
    args_string = build_args_string(args)

    """
    subscription #{operation_name}(#{args_string}) {
      #{operation_name}(#{args_string}) {
        data
        timestamp
      }
    }
    """
  end

  @doc """
  Parses GraphQL response and extracts tool results.
  """
  @spec parse_response(map()) :: {:ok, map()} | {:error, term()}
  def parse_response(response) do
    case response do
      %{"data" => data, "errors" => nil} ->
        {:ok, data}

      %{"data" => data, "errors" => errors} ->
        Logger.warning("GraphQL response contains errors: #{inspect(errors)}")
        {:ok, data}

      %{"errors" => errors} ->
        {:error, "GraphQL errors: #{inspect(errors)}"}

      _ ->
        {:error, "Invalid GraphQL response format"}
    end
  rescue
    error ->
      {:error, "Failed to parse GraphQL response: #{inspect(error)}"}
  end

  # Private functions

  defp extract_operation_tools(schema, operation_type, type_name) do
    case get_in(schema, ["__schema", "#{operation_type}Type"]) do
      nil ->
        []

      %{"name" => ^type_name} ->
        # Find the type definition
        types = get_in(schema, ["__schema", "types"]) || []

        type_def =
          Enum.find(types, fn type ->
            get_in(type, ["name"]) == type_name
          end)

        case type_def do
          nil ->
            []

          type ->
            fields = get_in(type, ["fields"]) || []

            Enum.map(fields, fn field ->
              build_tool_from_field(field, operation_type)
            end)
        end

      _ ->
        []
    end
  rescue
    error ->
      Logger.error("Failed to extract #{operation_type} tools: #{inspect(error)}")
      []
  end

  defp build_tool_from_field(field, operation_type) do
    name = get_in(field, ["name"]) || "unknown"
    description = get_in(field, ["description"]) || "No description available"

    # Extract arguments
    args = get_in(field, ["args"]) || []
    input_schema = build_input_schema(args)

    # Build outputs schema (simplified)
    output_schema = %{
      "type" => "object",
      "properties" => %{
        "result" => %{"type" => "any"},
        "success" => %{"type" => "boolean"},
        "error" => %{"type" => "string"}
      }
    }

    %{
      "name" => name,
      "description" => description,
      "inputs" => input_schema,
      "outputs" => output_schema,
      "tags" => ["graphql", operation_type],
      "operation_type" => operation_type
    }
  end

  defp build_input_schema(args) do
    properties =
      Enum.reduce(args, %{}, fn arg, acc ->
        name = get_in(arg, ["name"]) || "unknown"
        type_info = get_in(arg, ["type"]) || %{}
        elixir_type = graphql_type_to_elixir(type_info)

        Map.put(acc, name, %{
          "type" => elixir_type,
          "description" => get_in(arg, ["description"]) || "No description"
        })
      end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => []
    }
  end

  defp graphql_type_to_elixir(type_info) do
    case get_in(type_info, ["kind"]) do
      "SCALAR" ->
        case get_in(type_info, ["name"]) do
          "String" -> "string"
          "Int" -> "integer"
          "Float" -> "number"
          "Boolean" -> "boolean"
          "ID" -> "string"
          _ -> "any"
        end

      "NON_NULL" ->
        # Non-null type, get the inner type
        inner_type = get_in(type_info, ["ofType"])
        graphql_type_to_elixir(inner_type || %{})

      "LIST" ->
        # List type
        _inner_type = get_in(type_info, ["ofType"])
        "array"

      _ ->
        "any"
    end
  end

  defp build_args_string(args) when map_size(args) == 0 do
    ""
  end

  defp build_args_string(args) do
    args
    |> Enum.map_join(", ", fn {key, value} ->
      "$#{key}: #{value_to_graphql_type(value)}"
    end)
  end

  defp value_to_graphql_type(value) do
    case value do
      _ when is_binary(value) -> "String"
      _ when is_integer(value) -> "Int"
      _ when is_float(value) -> "Float"
      _ when is_boolean(value) -> "Boolean"
      _ when is_map(value) -> "JSON"
      _ when is_list(value) -> "[String]"
      _ -> "String"
    end
  end
end
