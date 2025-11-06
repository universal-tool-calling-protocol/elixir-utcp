defmodule ExUtcp.OpenApiConverter.AuthMapperTest do
  use ExUnit.Case, async: true

  alias ExUtcp.OpenApiConverter.Types, as: T
  alias ExUtcp.OpenApiConverter.{AuthMapper, Types}

  describe "map_security_scheme/1" do
    test "maps API key security scheme" do
      scheme = %T.ParsedSecurityScheme{
        name: "apiKey",
        type: "apiKey",
        description: "API key authentication",
        in: "header",
        scheme: nil,
        bearer_format: nil,
        flows: nil
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :api_key
      assert auth.api_key == "${API_KEY}"
      assert auth.location == :header
      assert auth.var_name == "apiKey"
    end

    test "maps HTTP basic security scheme" do
      scheme = %T.ParsedSecurityScheme{
        name: "basicAuth",
        type: "http",
        description: "Basic authentication",
        in: nil,
        scheme: "basic",
        bearer_format: nil,
        flows: nil
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :basic
      assert auth.username == "${USERNAME}"
      assert auth.password == "${PASSWORD}"
    end

    test "maps HTTP bearer security scheme" do
      scheme = %T.ParsedSecurityScheme{
        name: "bearerAuth",
        type: "http",
        description: "Bearer token authentication",
        in: nil,
        scheme: "bearer",
        bearer_format: "JWT",
        flows: nil
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :api_key
      assert auth.api_key == "Bearer ${API_KEY}"
      assert auth.location == :header
      assert auth.var_name == "Authorization"
    end

    test "maps OAuth2 client credentials flow" do
      flows = %T.OpenApiOAuthFlows{
        implicit: nil,
        password: nil,
        client_credentials: %T.OpenApiOAuthFlow{
          authorization_url: nil,
          token_url: "https://auth.example.com/token",
          refresh_url: nil,
          scopes: %{"read" => "Read access", "write" => "Write access"}
        },
        authorization_code: nil
      }

      scheme = %T.ParsedSecurityScheme{
        name: "oauth2",
        type: "oauth2",
        description: "OAuth2 authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: flows
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :oauth2
      assert auth.token_url == "https://auth.example.com/token"
      assert auth.client_id == "${CLIENT_ID}"
      assert auth.client_secret == "${CLIENT_SECRET}"
      assert auth.grant_type == "client_credentials"
      assert auth.scope == "read"
    end

    test "maps OAuth2 authorization code flow" do
      flows = %T.OpenApiOAuthFlows{
        implicit: nil,
        password: nil,
        client_credentials: nil,
        authorization_code: %T.OpenApiOAuthFlow{
          authorization_url: "https://auth.example.com/authorize",
          token_url: "https://auth.example.com/token",
          refresh_url: nil,
          scopes: %{"read" => "Read access"}
        }
      }

      scheme = %T.ParsedSecurityScheme{
        name: "oauth2",
        type: "oauth2",
        description: "OAuth2 authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: flows
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :oauth2
      assert auth.authorization_url == "https://auth.example.com/authorize"
      assert auth.token_url == "https://auth.example.com/token"
      assert auth.grant_type == "authorization_code"
    end

    test "maps OAuth2 password flow" do
      flows = %T.OpenApiOAuthFlows{
        implicit: nil,
        password: %T.OpenApiOAuthFlow{
          authorization_url: nil,
          token_url: "https://auth.example.com/token",
          refresh_url: nil,
          scopes: %{"read" => "Read access"}
        },
        client_credentials: nil,
        authorization_code: nil
      }

      scheme = %T.ParsedSecurityScheme{
        name: "oauth2",
        type: "oauth2",
        description: "OAuth2 authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: flows
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :oauth2
      assert auth.token_url == "https://auth.example.com/token"
      assert auth.grant_type == "password"
      assert auth.username == "${USERNAME}"
      assert auth.password == "${PASSWORD}"
    end

    test "maps OAuth2 implicit flow" do
      flows = %T.OpenApiOAuthFlows{
        implicit: %T.OpenApiOAuthFlow{
          authorization_url: "https://auth.example.com/authorize",
          token_url: nil,
          refresh_url: nil,
          scopes: %{"read" => "Read access"}
        },
        password: nil,
        client_credentials: nil,
        authorization_code: nil
      }

      scheme = %T.ParsedSecurityScheme{
        name: "oauth2",
        type: "oauth2",
        description: "OAuth2 authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: flows
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :oauth2
      assert auth.authorization_url == "https://auth.example.com/authorize"
      assert auth.grant_type == "implicit"
      assert auth.client_id == "${CLIENT_ID}"
    end

    test "maps OpenID Connect security scheme" do
      scheme = %T.ParsedSecurityScheme{
        name: "openIdConnect",
        type: "openIdConnect",
        description: "OpenID Connect authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: nil
      }

      auth = AuthMapper.map_security_scheme(scheme)

      assert auth.type == :oauth2
      assert auth.grant_type == "authorization_code"
      assert auth.scope == "openid"
    end

    test "returns nil for unsupported scheme type" do
      scheme = %T.ParsedSecurityScheme{
        name: "unsupported",
        type: "unsupported",
        description: "Unsupported authentication",
        in: nil,
        scheme: nil,
        bearer_format: nil,
        flows: nil
      }

      auth = AuthMapper.map_security_scheme(scheme)
      assert auth == nil
    end
  end

  describe "map_security_requirement/2" do
    test "maps security requirement to auth" do
      security_requirement = %{"apiKey" => []}

      security_schemes = %{
        "apiKey" => %T.ParsedSecurityScheme{
          name: "apiKey",
          type: "apiKey",
          description: "API key authentication",
          in: "header",
          scheme: nil,
          bearer_format: nil,
          flows: nil
        }
      }

      auth = AuthMapper.map_security_requirement(security_requirement, security_schemes)

      assert auth.type == :api_key
      assert auth.var_name == "apiKey"
    end

    test "returns nil for empty security requirement" do
      security_requirement = %{}
      security_schemes = %{}

      auth = AuthMapper.map_security_requirement(security_requirement, security_schemes)
      assert auth == nil
    end

    test "returns nil for missing security scheme" do
      security_requirement = %{"missing" => []}
      security_schemes = %{}

      auth = AuthMapper.map_security_requirement(security_requirement, security_schemes)
      assert auth == nil
    end
  end

  describe "map_all_security_schemes/1" do
    test "maps all security schemes" do
      security_schemes = %{
        "apiKey" => %T.ParsedSecurityScheme{
          name: "apiKey",
          type: "apiKey",
          description: "API key authentication",
          in: "header",
          scheme: nil,
          bearer_format: nil,
          flows: nil
        },
        "basicAuth" => %T.ParsedSecurityScheme{
          name: "basicAuth",
          type: "http",
          description: "Basic authentication",
          in: nil,
          scheme: "basic",
          bearer_format: nil,
          flows: nil
        }
      }

      auths = AuthMapper.map_all_security_schemes(security_schemes)

      assert length(auths) == 2
      assert Enum.any?(auths, &(&1.type == :api_key))
      assert Enum.any?(auths, &(&1.type == :basic))
    end
  end

  describe "validate_auth/2" do
    test "validates API key auth against matching scheme" do
      auth = %{
        type: :api_key,
        api_key: "${API_KEY}",
        location: :header,
        var_name: "X-API-Key"
      }

      security_schemes = %{
        "apiKey" => %T.ParsedSecurityScheme{
          name: "apiKey",
          type: "apiKey",
          description: "API key authentication",
          in: "header",
          scheme: nil,
          bearer_format: nil,
          flows: nil
        }
      }

      {:ok, validated_auth} = AuthMapper.validate_auth(auth, security_schemes)
      assert validated_auth == auth
    end

    test "validates basic auth against matching scheme" do
      auth = %{
        type: :basic,
        username: "${USERNAME}",
        password: "${PASSWORD}"
      }

      security_schemes = %{
        "basicAuth" => %T.ParsedSecurityScheme{
          name: "basicAuth",
          type: "http",
          description: "Basic authentication",
          in: nil,
          scheme: "basic",
          bearer_format: nil,
          flows: nil
        }
      }

      {:ok, validated_auth} = AuthMapper.validate_auth(auth, security_schemes)
      assert validated_auth == auth
    end

    test "validates OAuth2 auth against matching scheme" do
      auth = %{
        type: :oauth2,
        token_url: "https://auth.example.com/token",
        client_id: "${CLIENT_ID}",
        client_secret: "${CLIENT_SECRET}",
        scope: "read",
        grant_type: "client_credentials"
      }

      security_schemes = %{
        "oauth2" => %T.ParsedSecurityScheme{
          name: "oauth2",
          type: "oauth2",
          description: "OAuth2 authentication",
          in: nil,
          scheme: nil,
          bearer_format: nil,
          flows: nil
        }
      }

      {:ok, validated_auth} = AuthMapper.validate_auth(auth, security_schemes)
      assert validated_auth == auth
    end

    test "returns error for API key auth without matching scheme" do
      auth = %{
        type: :api_key,
        api_key: "${API_KEY}",
        location: :header,
        var_name: "X-API-Key"
      }

      security_schemes = %{}

      {:error, reason} = AuthMapper.validate_auth(auth, security_schemes)
      assert reason == "No API key security scheme found in OpenAPI spec"
    end

    test "returns error for basic auth without matching scheme" do
      auth = %{
        type: :basic,
        username: "${USERNAME}",
        password: "${PASSWORD}"
      }

      security_schemes = %{}

      {:error, reason} = AuthMapper.validate_auth(auth, security_schemes)
      assert reason == "No HTTP basic security scheme found in OpenAPI spec"
    end

    test "returns error for OAuth2 auth without matching scheme" do
      auth = %{
        type: :oauth2,
        token_url: "https://auth.example.com/token",
        client_id: "${CLIENT_ID}",
        client_secret: "${CLIENT_SECRET}",
        scope: "read",
        grant_type: "client_credentials"
      }

      security_schemes = %{}

      {:error, reason} = AuthMapper.validate_auth(auth, security_schemes)
      assert reason == "No OAuth2 security scheme found in OpenAPI spec"
    end

    test "returns error for unsupported auth type" do
      auth = %{type: :unsupported}

      security_schemes = %{}

      {:error, reason} = AuthMapper.validate_auth(auth, security_schemes)
      assert reason == "Unsupported authentication type"
    end
  end
end
