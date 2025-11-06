defmodule ExUtcp.OpenApiConverter.Types do
  @moduledoc """
  Types and data structures for OpenAPI Converter.
  """

  # OpenAPI 2.0 (Swagger) Types

  defmodule SwaggerSpec do
    @moduledoc "OpenAPI 2.0 (Swagger) specification structure"
    defstruct [
      :swagger,
      :info,
      :host,
      :base_path,
      :schemes,
      :consumes,
      :produces,
      :paths,
      :definitions,
      :parameters,
      :responses,
      :security_definitions,
      :security,
      :tags,
      :external_docs
    ]
  end

  defmodule SwaggerInfo do
    @moduledoc "OpenAPI 2.0 info section"
    defstruct [
      :title,
      :description,
      :terms_of_service,
      :contact,
      :license,
      :version
    ]
  end

  defmodule SwaggerPath do
    @moduledoc "OpenAPI 2.0 path item"
    defstruct [
      :get,
      :put,
      :post,
      :delete,
      :options,
      :head,
      :patch,
      :parameters
    ]
  end

  defmodule SwaggerOperation do
    @moduledoc "OpenAPI 2.0 operation"
    defstruct [
      :tags,
      :summary,
      :description,
      :external_docs,
      :operation_id,
      :consumes,
      :produces,
      :parameters,
      :responses,
      :schemes,
      :deprecated,
      :security
    ]
  end

  defmodule SwaggerParameter do
    @moduledoc "OpenAPI 2.0 parameter"
    defstruct [
      :name,
      :in,
      :description,
      :required,
      :schema,
      :type,
      :format,
      :allow_empty_value,
      :items,
      :collection_format,
      :default,
      :maximum,
      :exclusive_maximum,
      :minimum,
      :exclusive_minimum,
      :max_length,
      :min_length,
      :pattern,
      :max_items,
      :min_items,
      :unique_items,
      :enum,
      :multiple_of
    ]
  end

  defmodule SwaggerResponse do
    @moduledoc "OpenAPI 2.0 response"
    defstruct [
      :description,
      :schema,
      :headers,
      :examples
    ]
  end

  defmodule SwaggerSchema do
    @moduledoc "OpenAPI 2.0 schema"
    defstruct [
      :type,
      :format,
      :title,
      :description,
      :default,
      :multiple_of,
      :maximum,
      :exclusive_maximum,
      :minimum,
      :exclusive_minimum,
      :max_length,
      :min_length,
      :pattern,
      :max_items,
      :min_items,
      :unique_items,
      :max_properties,
      :min_properties,
      :required,
      :enum,
      :properties,
      :items,
      :all_of,
      :one_of,
      :any_of,
      :not,
      :additional_properties,
      :discriminator,
      :read_only,
      :xml,
      :external_docs,
      :example
    ]
  end

  defmodule SwaggerSecurityDefinition do
    @moduledoc "OpenAPI 2.0 security definition"
    defstruct [
      :type,
      :description,
      :name,
      :in,
      :flow,
      :authorization_url,
      :token_url,
      :scopes
    ]
  end

  # OpenAPI 3.0 Types

  defmodule OpenApiSpec do
    @moduledoc "OpenAPI 3.0 specification structure"
    defstruct [
      :openapi,
      :info,
      :servers,
      :paths,
      :components,
      :security,
      :tags,
      :external_docs
    ]
  end

  defmodule OpenApiInfo do
    @moduledoc "OpenAPI 3.0 info section"
    defstruct [
      :title,
      :description,
      :terms_of_service,
      :contact,
      :license,
      :version
    ]
  end

  defmodule OpenApiServer do
    @moduledoc "OpenAPI 3.0 server"
    defstruct [
      :url,
      :description,
      :variables
    ]
  end

  defmodule OpenApiPathItem do
    @moduledoc "OpenAPI 3.0 path item"
    defstruct [
      :summary,
      :description,
      :get,
      :put,
      :post,
      :delete,
      :options,
      :head,
      :patch,
      :trace,
      :servers,
      :parameters
    ]
  end

  defmodule OpenApiOperation do
    @moduledoc "OpenAPI 3.0 operation"
    defstruct [
      :tags,
      :summary,
      :description,
      :external_docs,
      :operation_id,
      :parameters,
      :request_body,
      :responses,
      :callbacks,
      :deprecated,
      :security,
      :servers
    ]
  end

  defmodule OpenApiParameter do
    @moduledoc "OpenAPI 3.0 parameter"
    defstruct [
      :name,
      :in,
      :description,
      :required,
      :deprecated,
      :allow_empty_value,
      :style,
      :explode,
      :allow_reserved,
      :schema,
      :example,
      :examples
    ]
  end

  defmodule OpenApiRequestBody do
    @moduledoc "OpenAPI 3.0 request body"
    defstruct [
      :description,
      :content,
      :required
    ]
  end

  defmodule OpenApiResponse do
    @moduledoc "OpenAPI 3.0 response"
    defstruct [
      :description,
      :headers,
      :content,
      :links
    ]
  end

  defmodule OpenApiMediaType do
    @moduledoc "OpenAPI 3.0 media type"
    defstruct [
      :schema,
      :example,
      :examples,
      :encoding
    ]
  end

  defmodule OpenApiSchema do
    @moduledoc "OpenAPI 3.0 schema"
    defstruct [
      :type,
      :format,
      :title,
      :description,
      :default,
      :multiple_of,
      :maximum,
      :exclusive_maximum,
      :minimum,
      :exclusive_minimum,
      :max_length,
      :min_length,
      :pattern,
      :max_items,
      :min_items,
      :unique_items,
      :max_properties,
      :min_properties,
      :required,
      :enum,
      :properties,
      :items,
      :all_of,
      :one_of,
      :any_of,
      :not,
      :additional_properties,
      :discriminator,
      :read_only,
      :write_only,
      :xml,
      :external_docs,
      :example,
      :deprecated
    ]
  end

  defmodule OpenApiComponents do
    @moduledoc "OpenAPI 3.0 components"
    defstruct [
      :schemas,
      :responses,
      :parameters,
      :examples,
      :request_bodies,
      :headers,
      :security_schemes,
      :links,
      :callbacks
    ]
  end

  defmodule OpenApiSecurityScheme do
    @moduledoc "OpenAPI 3.0 security scheme"
    defstruct [
      :type,
      :description,
      :name,
      :in,
      :scheme,
      :bearer_format,
      :flows,
      :open_id_connect_url
    ]
  end

  defmodule OpenApiOAuthFlows do
    @moduledoc "OpenAPI 3.0 OAuth flows"
    defstruct [
      :implicit,
      :password,
      :client_credentials,
      :authorization_code
    ]
  end

  defmodule OpenApiOAuthFlow do
    @moduledoc "OpenAPI 3.0 OAuth flow"
    defstruct [
      :authorization_url,
      :token_url,
      :refresh_url,
      :scopes
    ]
  end

  # Common types

  defmodule Contact do
    @moduledoc "Contact information"
    defstruct [
      :name,
      :url,
      :email
    ]
  end

  defmodule License do
    @moduledoc "License information"
    defstruct [
      :name,
      :url
    ]
  end

  defmodule ExternalDocs do
    @moduledoc "External documentation"
    defstruct [
      :description,
      :url
    ]
  end

  defmodule Tag do
    @moduledoc "Tag information"
    defstruct [
      :name,
      :description,
      :external_docs
    ]
  end

  # Parsed specification structure

  defmodule ParsedSpec do
    @moduledoc "Parsed OpenAPI specification"
    defstruct [
      :version,
      :info,
      :servers,
      :paths,
      :components,
      :security,
      :tags,
      :external_docs
    ]
  end

  defmodule ParsedInfo do
    @moduledoc "Parsed info section"
    defstruct [
      :title,
      :description,
      :version,
      :contact,
      :license
    ]
  end

  defmodule ParsedServer do
    @moduledoc "Parsed server information"
    defstruct [
      :url,
      :description,
      :variables
    ]
  end

  defmodule ParsedPath do
    @moduledoc "Parsed path information"
    defstruct [
      :path,
      :operations
    ]
  end

  defmodule ParsedOperation do
    @moduledoc "Parsed operation information"
    defstruct [
      :method,
      :path,
      :operation_id,
      :summary,
      :description,
      :tags,
      :parameters,
      :request_body,
      :responses,
      :security,
      :deprecated
    ]
  end

  defmodule ParsedParameter do
    @moduledoc "Parsed parameter information"
    defstruct [
      :name,
      :in,
      :description,
      :required,
      :schema,
      :style,
      :explode,
      :example
    ]
  end

  defmodule ParsedRequestBody do
    @moduledoc "Parsed request body information"
    defstruct [
      :description,
      :required,
      :content_types,
      :schema
    ]
  end

  defmodule ParsedResponse do
    @moduledoc "Parsed response information"
    defstruct [
      :status_code,
      :description,
      :content_types,
      :schema
    ]
  end

  defmodule ParsedSecurityScheme do
    @moduledoc "Parsed security scheme information"
    defstruct [
      :name,
      :type,
      :description,
      :in,
      :scheme,
      :bearer_format,
      :flows
    ]
  end

  # Conversion options

  defmodule ConversionOptions do
    @moduledoc "OpenAPI conversion options"
    defstruct [
      :base_url,
      :auth,
      :prefix,
      :include_deprecated,
      :filter_tags,
      :exclude_tags,
      :custom_headers,
      :timeout
    ]
  end

  # Validation results

  defmodule ValidationResult do
    @moduledoc "OpenAPI validation result"
    defstruct [
      :valid,
      :errors,
      :warnings,
      :version,
      :operations_count,
      :security_schemes_count
    ]
  end

  defmodule ValidationError do
    @moduledoc "Validation error"
    defstruct [
      :path,
      :message,
      :code
    ]
  end
end
