defmodule ExUtcp.Config do
  @moduledoc """
  Configuration management for UTCP client.

  Handles variable substitution, environment variable loading, and provider configuration.
  """

  alias ExUtcp.Types, as: T

  @doc """
  Creates a new client configuration with default values.
  """
  @spec new(keyword()) :: T.client_config()
  def new(opts \\ []) do
    %{
      variables: Keyword.get(opts, :variables, %{}),
      providers_file_path: Keyword.get(opts, :providers_file_path, nil),
      load_variables_from: Keyword.get(opts, :load_variables_from, [])
    }
  end

  @doc """
  Loads variables from a .env file.
  """
  @spec load_from_env_file(String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, any()}
  def load_from_env_file(path) do
    case Dotenvy.source(path) do
      {:ok, env_vars} -> {:ok, env_vars}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a variable value from the configuration, checking in order:
  1. Inline variables
  2. Loaded variable sources
  3. System environment variables
  """
  @spec get_variable(T.client_config(), String.t()) ::
          {:ok, String.t()} | {:error, T.variable_not_found()}
  def get_variable(config, key) do
    # Check inline variables first
    case Map.get(config.variables, key) do
      nil ->
        # Check loaded variable sources
        case get_from_loaders(config.load_variables_from, key) do
          {:ok, value} ->
            {:ok, value}

          :error ->
            # Check system environment
            case System.get_env(key) do
              nil -> {:error, %{__exception__: true, variable_name: key}}
              value -> {:ok, value}
            end
        end

      value ->
        {:ok, value}
    end
  end

  @doc """
  Substitutes variables in a value using the pattern ${VAR} or $VAR.
  """
  @spec substitute_variables(T.client_config(), any()) :: any()
  def substitute_variables(config, value) when is_binary(value) do
    Regex.replace(~r/\$\{(\w+)\}|\$(\w+)/, value, fn match, var1, var2 ->
      var_name = if var1 == "", do: var2, else: var1

      case get_variable(config, var_name) do
        {:ok, replacement} -> replacement
        {:error, _} -> match
      end
    end)
  end

  def substitute_variables(config, value) when is_list(value) do
    Enum.map(value, &substitute_variables(config, &1))
  end

  def substitute_variables(config, value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, substitute_variables(config, v)} end)
  end

  def substitute_variables(_config, value), do: value

  # Private helper to get variable from loaders
  defp get_from_loaders(loaders, key) do
    Enum.reduce_while(loaders, :error, fn loader, _acc ->
      case loader.get(key) do
        {:ok, value} when value != "" -> {:halt, {:ok, value}}
        _ -> {:cont, :error}
      end
    end)
  end
end
