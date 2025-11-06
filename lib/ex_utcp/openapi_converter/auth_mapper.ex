defmodule ExUtcp.OpenApiConverter.AuthMapper do
  @moduledoc """
  Maps OpenAPI security schemes to UTCP authentication configurations.
  """

  alias ExUtcp.OpenApiConverter.Types, as: T

  @doc """
  Maps OpenAPI security schemes to UTCP authentication.

  ## Parameters

  - `security_requirement`: OpenAPI security requirement
  - `security_schemes`: Available security schemes

  ## Returns

  UTCP authentication configuration or nil.
  """
  @spec map_security_requirement(map(), map()) :: map() | nil
  def map_security_requirement(security_requirement, security_schemes) do
    case Map.keys(security_requirement) do
      [] ->
        nil

      [scheme_name | _] ->
        case Map.get(security_schemes, scheme_name) do
          nil -> nil
          scheme -> map_security_scheme(scheme)
        end
    end
  end

  @doc """
  Maps a single OpenAPI security scheme to UTCP authentication.

  ## Parameters

  - `scheme`: OpenAPI security scheme

  ## Returns

  UTCP authentication configuration or nil.
  """
  @spec map_security_scheme(T.ParsedSecurityScheme.t()) :: map() | nil
  def map_security_scheme(scheme) do
    case scheme.type do
      "apiKey" -> map_api_key_auth(scheme)
      "http" -> map_http_auth(scheme)
      "oauth2" -> map_oauth2_auth(scheme)
      "openIdConnect" -> map_openid_connect_auth(scheme)
      _ -> nil
    end
  end

  # Private functions

  defp map_api_key_auth(scheme) do
    location =
      case scheme.in do
        "header" -> :header
        "query" -> :query
        "cookie" -> :cookie
        _ -> :header
      end

    %{
      type: :api_key,
      api_key: "${API_KEY}",
      location: location,
      var_name: scheme.name || "X-API-Key"
    }
  end

  defp map_http_auth(scheme) do
    case scheme.scheme do
      "bearer" -> map_bearer_auth(scheme)
      "basic" -> map_basic_auth(scheme)
      _ -> nil
    end
  end

  defp map_bearer_auth(_scheme) do
    %{
      type: :api_key,
      api_key: "Bearer ${API_KEY}",
      location: :header,
      var_name: "Authorization"
    }
  end

  defp map_basic_auth(_scheme) do
    %{
      type: :basic,
      username: "${USERNAME}",
      password: "${PASSWORD}"
    }
  end

  defp map_oauth2_auth(scheme) do
    case scheme.flows do
      nil ->
        nil

      flows ->
        # Prefer client_credentials flow for API usage
        cond do
          flows.client_credentials -> map_client_credentials_flow(flows.client_credentials)
          flows.authorization_code -> map_authorization_code_flow(flows.authorization_code)
          flows.password -> map_password_flow(flows.password)
          flows.implicit -> map_implicit_flow(flows.implicit)
          true -> nil
        end
    end
  end

  defp map_client_credentials_flow(flow) do
    %{
      type: :oauth2,
      token_url: flow.token_url || "${TOKEN_URL}",
      client_id: "${CLIENT_ID}",
      client_secret: "${CLIENT_SECRET}",
      scope: get_default_scope(flow.scopes),
      grant_type: "client_credentials"
    }
  end

  defp map_authorization_code_flow(flow) do
    %{
      type: :oauth2,
      token_url: flow.token_url || "${TOKEN_URL}",
      client_id: "${CLIENT_ID}",
      client_secret: "${CLIENT_SECRET}",
      scope: get_default_scope(flow.scopes),
      grant_type: "authorization_code",
      authorization_url: flow.authorization_url || "${AUTHORIZATION_URL}"
    }
  end

  defp map_password_flow(flow) do
    %{
      type: :oauth2,
      token_url: flow.token_url || "${TOKEN_URL}",
      client_id: "${CLIENT_ID}",
      client_secret: "${CLIENT_SECRET}",
      scope: get_default_scope(flow.scopes),
      grant_type: "password",
      username: "${USERNAME}",
      password: "${PASSWORD}"
    }
  end

  defp map_implicit_flow(flow) do
    %{
      type: :oauth2,
      client_id: "${CLIENT_ID}",
      scope: get_default_scope(flow.scopes),
      grant_type: "implicit",
      authorization_url: flow.authorization_url || "${AUTHORIZATION_URL}"
    }
  end

  defp map_openid_connect_auth(_scheme) do
    # OpenID Connect is not directly supported in UTCP auth types
    # Map to OAuth2 with OpenID Connect discovery
    %{
      type: :oauth2,
      token_url: "${TOKEN_URL}",
      client_id: "${CLIENT_ID}",
      client_secret: "${CLIENT_SECRET}",
      scope: "openid",
      grant_type: "authorization_code",
      authorization_url: "${AUTHORIZATION_URL}"
    }
  end

  defp get_default_scope(scopes) when is_map(scopes) do
    case Map.keys(scopes) do
      [] -> ""
      [scope | _] -> scope
    end
  end

  defp get_default_scope(_), do: ""

  @doc """
  Maps multiple security schemes to a list of authentication options.

  ## Parameters

  - `security_schemes`: Map of security schemes

  ## Returns

  List of UTCP authentication configurations.
  """
  @spec map_all_security_schemes(map()) :: [map()]
  def map_all_security_schemes(security_schemes) do
    Enum.map(security_schemes, fn {_name, scheme} ->
      map_security_scheme(scheme)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Creates authentication configuration for tools that require auth.

  ## Parameters

  - `security_schemes`: Available security schemes
  - `operation_security`: Security requirements for the operation

  ## Returns

  UTCP authentication configuration or nil.
  """
  @spec create_tool_auth(map(), list()) :: map() | nil
  def create_tool_auth(security_schemes, operation_security) do
    case operation_security do
      [] ->
        nil

      [security_requirement | _] ->
        map_security_requirement(security_requirement, security_schemes)
    end
  end

  @doc """
  Validates authentication configuration against OpenAPI security schemes.

  ## Parameters

  - `auth`: UTCP authentication configuration
  - `security_schemes`: Available security schemes

  ## Returns

  `{:ok, validated_auth}` or `{:error, reason}`.
  """
  @spec validate_auth(map(), map()) :: {:ok, map()} | {:error, term()}
  def validate_auth(auth, security_schemes) do
    case auth do
      %{type: :api_key} -> validate_api_key_auth(auth, security_schemes)
      %{type: :basic} -> validate_basic_auth(auth, security_schemes)
      %{type: :oauth2} -> validate_oauth2_auth(auth, security_schemes)
      _ -> {:error, "Unsupported authentication type"}
    end
  end

  defp validate_api_key_auth(auth, security_schemes) do
    # Check if there's a matching API key security scheme
    has_api_key_scheme =
      Enum.any?(security_schemes, fn {_name, scheme} ->
        scheme.type == "apiKey"
      end)

    if has_api_key_scheme do
      {:ok, auth}
    else
      {:error, "No API key security scheme found in OpenAPI spec"}
    end
  end

  defp validate_basic_auth(auth, security_schemes) do
    # Check if there's a matching HTTP basic security scheme
    has_basic_scheme =
      Enum.any?(security_schemes, fn {_name, scheme} ->
        scheme.type == "http" && scheme.scheme == "basic"
      end)

    if has_basic_scheme do
      {:ok, auth}
    else
      {:error, "No HTTP basic security scheme found in OpenAPI spec"}
    end
  end

  defp validate_oauth2_auth(auth, security_schemes) do
    # Check if there's a matching OAuth2 security scheme
    has_oauth2_scheme =
      Enum.any?(security_schemes, fn {_name, scheme} ->
        scheme.type == "oauth2"
      end)

    if has_oauth2_scheme do
      {:ok, auth}
    else
      {:error, "No OAuth2 security scheme found in OpenAPI spec"}
    end
  end
end
