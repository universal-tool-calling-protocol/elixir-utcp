defmodule ExUtcp.Auth do
  @moduledoc """
  Authentication mechanisms for UTCP providers.

  This module handles various authentication types including API key, Basic Auth, and OAuth2.
  """

  alias ExUtcp.Types, as: T

  @doc """
  Creates a new API key authentication configuration.
  """
  @spec new_api_key_auth(keyword()) :: T.api_key_auth()
  def new_api_key_auth(opts) do
    %{
      type: "api_key",
      api_key: Keyword.fetch!(opts, :api_key),
      location: Keyword.get(opts, :location, "header"),
      var_name: Keyword.get(opts, :var_name, "Authorization")
    }
  end

  @doc """
  Creates a new Basic authentication configuration.
  """
  @spec new_basic_auth(keyword()) :: T.basic_auth()
  def new_basic_auth(opts) do
    %{
      type: "basic",
      username: Keyword.fetch!(opts, :username),
      password: Keyword.fetch!(opts, :password)
    }
  end

  @doc """
  Creates a new OAuth2 authentication configuration.
  """
  @spec new_oauth2_auth(keyword()) :: T.oauth2_auth()
  def new_oauth2_auth(opts) do
    %{
      type: "oauth2",
      client_id: Keyword.fetch!(opts, :client_id),
      client_secret: Keyword.fetch!(opts, :client_secret),
      token_url: Keyword.fetch!(opts, :token_url),
      scope: Keyword.fetch!(opts, :scope)
    }
  end

  @doc """
  Applies authentication to HTTP headers based on the auth configuration.
  """
  @spec apply_to_headers(T.auth(), map()) :: map()
  def apply_to_headers(auth, headers) when is_map(auth) do
    case auth.type do
      "api_key" -> apply_api_key_auth(auth, headers)
      "basic" -> apply_basic_auth(auth, headers)
      # OAuth2 requires token exchange, handled separately
      "oauth2" -> headers
      _ -> headers
    end
  end

  def apply_to_headers(_auth, headers), do: headers

  @doc """
  Applies API key authentication to headers.
  """
  @spec apply_api_key_auth(T.api_key_auth(), map()) :: map()
  def apply_api_key_auth(auth, headers) do
    case auth.location do
      "header" ->
        Map.put(headers, auth.var_name, auth.api_key)

      "query" ->
        # Query params are handled separately
        headers

      "cookie" ->
        Map.put(headers, "Cookie", "#{auth.var_name}=#{auth.api_key}")

      _ ->
        headers
    end
  end

  @doc """
  Applies Basic authentication to headers.
  """
  @spec apply_basic_auth(T.basic_auth(), map()) :: map()
  def apply_basic_auth(auth, headers) do
    credentials = Base.encode64("#{auth.username}:#{auth.password}")
    Map.put(headers, "Authorization", "Basic #{credentials}")
  end

  @doc """
  Validates an authentication configuration.
  """
  @spec validate_auth(T.auth()) :: :ok | {:error, String.t()}
  def validate_auth(auth) do
    case auth.type do
      "api_key" ->
        if is_nil(auth.api_key) or auth.api_key == "" do
          {:error, "API key is required for API key authentication"}
        else
          :ok
        end

      "basic" ->
        if is_nil(auth.username) or auth.username == "" or
             is_nil(auth.password) or auth.password == "" do
          {:error, "Username and password are required for Basic authentication"}
        else
          :ok
        end

      "oauth2" ->
        if is_nil(auth.client_id) or auth.client_id == "" or
             is_nil(auth.client_secret) or auth.client_secret == "" or
             is_nil(auth.token_url) or auth.token_url == "" or
             is_nil(auth.scope) or auth.scope == "" do
          {:error,
           "Client ID, client secret, token URL, and scope are required for OAuth2 authentication"}
        else
          :ok
        end

      _ ->
        {:error, "Unknown authentication type: #{auth.type}"}
    end
  end
end
