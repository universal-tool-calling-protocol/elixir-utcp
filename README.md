# ExUtcp

[![Hex.pm](https://img.shields.io/hexpm/v/ex_utcp.svg)](https://hex.pm/packages/ex_utcp)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_utcp.svg)](https://hex.pm/packages/ex_utcp)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_utcp.svg)](https://hex.pm/packages/ex_utcp)
[![HexDocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_utcp)

Elixir implementation of the Universal Tool Calling Protocol (UTCP).


<img width="512" height="512" alt="ex_utcp-2" src="https://github.com/user-attachments/assets/a4f5592e-4d16-42b2-8e98-b79bd164df8b" />




## Introduction

The Universal Tool Calling Protocol (UTCP) is a standard for defining and interacting with tools across communication protocols. UTCP emphasizes scalability, interoperability, and ease of use.

Key characteristics:
* **Scalability**: Handles large numbers of tools and providers without performance degradation
* **Interoperability**: Supports multiple provider types including HTTP, [WebSockets](https://tools.ietf.org/html/rfc6455), [gRPC](https://grpc.io/), and CLI tools
* **Ease of Use**: Built on simple, well-defined patterns

## Features

* Transports: HTTP, CLI, WebSocket, gRPC, GraphQL, MCP, TCP/UDP, WebRTC
* Streaming support across all transports
* OpenAPI Converter: Automatic API discovery and tool generation
* Variable substitution via environment variables or `.env` files
* In-memory repository for providers and tools
* Authentication: API Key, Basic, OAuth2
* Connection pooling and lifecycle management
* Test configuration with integration test exclusion by default
* Advanced Search: Multiple algorithms with fuzzy matching and semantic search
* Monitoring and Metrics: Telemetry, PromEx, health checks, and performance monitoring
* Comprehensive test suite with 497+ tests

## Installation

Add `ex_utcp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_utcp, "~> 0.2.0"}
  ]
end
```

## Getting Started

### Basic Usage

```elixir
alias ExUtcp.{Client, Config}

# Create a client configuration
config = Config.new(providers_file_path: "providers.json")

# Start a UTCP client
{:ok, client} = Client.start_link(config)

# Search for tools
{:ok, tools} = Client.search_tools(client, "", 10)

# Call a tool
{:ok, result} = Client.call_tool(client, "provider.tool_name", %{"arg" => "value"})
```

### Programmatic Provider Registration

```elixir
alias ExUtcp.{Client, Config, Providers}

# Create a client
config = Config.new()
{:ok, client} = Client.start_link(config)

# Create an HTTP provider
provider = Providers.new_http_provider([
  name: "my_api",
  url: "https://api.example.com/tools",
  http_method: "POST"
])

# Register the provider
{:ok, tools} = Client.register_tool_provider(client, provider)

# Call a discovered tool
{:ok, result} = Client.call_tool(client, "my_api.echo", %{"message" => "Hello!"})
```

### CLI Provider Example

```elixir
alias ExUtcp.{Client, Config, Providers}

# Create a client
config = Config.new()
{:ok, client} = Client.start_link(config)

# Create a CLI provider
provider = Providers.new_cli_provider([
  name: "my_script",
  command_name: "python my_script.py",
  working_dir: "/path/to/script"
])

# Register the provider
{:ok, tools} = Client.register_tool_provider(client, provider)

# Call a tool
{:ok, result} = Client.call_tool(client, "my_script.greet", %{"name" => "World"})
```

## Configuration

### Provider Configuration File

Create a `providers.json` file to define your providers:

```json
{
  "providers": [
    {
      "name": "http_api",
      "type": "http",
      "http_method": "POST",
      "url": "https://api.example.com/tools",
      "content_type": "application/json",
      "headers": {
        "User-Agent": "ExUtcp/0.2.0"
      },
      "auth": {
        "type": "api_key",
        "api_key": "${API_KEY}",
        "location": "header",
        "var_name": "Authorization"
      }
    },
    {
      "name": "cli_tool",
      "type": "cli",
      "command_name": "python my_tool.py",
      "working_dir": "/opt/tools",
      "env_vars": {
        "PYTHONPATH": "/opt/tools"
      }
    }
  ]
}
```

### Variable Substitution

UTCP supports variable substitution using `${VAR}` or `$VAR` syntax:

```elixir
# Load variables from .env file
{:ok, env_vars} = Config.load_from_env_file(".env")

config = Config.new(
  variables: env_vars,
  providers_file_path: "providers.json"
)
```

## OpenAPI Converter

The OpenAPI Converter automatically discovers and converts OpenAPI specifications into UTCP tools.

### Basic Usage

```elixir
alias ExUtcp.{Client, Config}

# Create a client
{:ok, client} = Client.start_link(%{providers_file_path: nil, variables: %{}})

# Convert OpenAPI spec from URL
{:ok, tools} = Client.convert_openapi(client, "https://api.example.com/openapi.json")

# Convert OpenAPI spec from file
{:ok, tools} = Client.convert_openapi(client, "path/to/spec.yaml")

# Convert with options
{:ok, tools} = Client.convert_openapi(client, spec, %{
  prefix: "my_api",
  auth: %{type: "api_key", api_key: "Bearer ${API_KEY}"}
})
```

### Supported Formats

- OpenAPI 2.0 (Swagger)
- OpenAPI 3.0
- JSON and YAML specifications
- URL and file-based specifications

### Authentication Mapping

The converter automatically maps OpenAPI security schemes to UTCP authentication:

- API Key authentication
- HTTP Basic authentication
- HTTP Bearer authentication
- OAuth2 flows
- OpenID Connect

## Architecture

The library is organized into several main components:

* ExUtcp.Client - Main client interface
* ExUtcp.Config - Configuration management
* ExUtcp.Providers - Provider implementations for different protocols
* ExUtcp.Transports - Transport layer implementations
* ExUtcp.Tools - Tool definitions and management
* ExUtcp.Repository - Tool and provider storage
* ExUtcp.OpenApiConverter - OpenAPI specification conversion

## Implementation Status

### Gap Analysis: UTCP Implementations Comparison

| Feature Category | Python UTCP | Go UTCP | Elixir UTCP | Elixir Coverage |
|------------------|-------------|---------|-------------|-----------------|
| **Core Architecture** | | | | |
| Core Client | Complete | Complete | Complete | 100% |
| Configuration | Complete | Complete | Enhanced | 100% |
| Variable Substitution | Complete | Complete | Complete | 100% |
| **Transports** | | | | |
| HTTP/HTTPS | Complete | Complete | Complete | 100% |
| CLI | Complete | Complete | Complete | 100% |
| WebSocket | Complete | Complete | Complete | 100% |
| gRPC | Complete | Complete | Complete | 100% |
| GraphQL | Complete | Complete | Complete | 100% |
| MCP | Complete | Complete | Complete | 100% |
| SSE | Complete | Complete | Complete | 100% |
| Streamable HTTP | Complete | Complete | Complete | 100% |
| TCP/UDP | Complete | Complete | Complete | 100% |
| WebRTC | Complete | Complete | Complete | 100% |
| **Authentication** | | | | |
| API Key | Complete | Complete | Complete | 100% |
| Basic Auth | Complete | Complete | Complete | 100% |
| OAuth2 | Complete | Complete | Complete | 100% |
| **Advanced Features** | | | | |
| Streaming | Complete | Complete | Complete | 100% |
| Connection Pooling | Complete | Complete | Complete | 100% |
| Error Recovery | Complete | Complete | Complete | 100% |
| OpenAPI Converter | Complete | Complete | Complete | 100% |
| Tool Discovery | Complete | Complete | Complete | 100% |
| Search | Advanced | Advanced | Complete | 100% |
| **Testing** | | | | |
| Unit Tests | Complete | Complete | Complete | 100% |
| Integration Tests | Complete | Complete | Complete | 100% |
| Mock Testing | Complete | Complete | Complete | 100% |
| Test Coverage | High | High | High | 100% |
| **Performance** | | | | |
| Connection Management | Optimized | Optimized | Optimized | 100% |
| Memory Usage | Optimized | Optimized | Optimized | 100% |
| Throughput | High | High | High | 100% |
| **Monitoring** | | | | |
| Telemetry | Complete | Complete | Complete | 100% |
| Metrics | Complete | Complete | Complete | 100% |
| Health Checks | Complete | Complete | Complete | 100% |
| Performance Monitoring | Complete | Complete | Complete | 100% |
| **Documentation** | | | | |
| API Docs | Complete | Complete | Complete | 100% |
| Examples | Complete | Complete | Complete | 100% |
| Guides | Complete | Complete | Complete | 100% |

### Priority Recommendations

#### High Priority
- [x] OpenAPI Converter: Automatic API discovery and tool generation
- [x] TCP/UDP Transport: Low-level network protocols
- [x] Advanced Search: Sophisticated search algorithms
- [x] Monitoring: Metrics and health checks
- [x] WebRTC Transport: Peer-to-peer communication

#### Medium Priority
- [ ] Batch Operations: Multiple tool calls

#### Low Priority
- [ ] Custom Variable Loaders: Beyond .env files
- [ ] API Documentation Generation

### Implementation Status

#### Completed Features
- 8 transports: HTTP, CLI, WebSocket, gRPC, GraphQL, MCP, TCP/UDP, WebRTC
- Streaming support across all transports
- OpenAPI Converter: Automatic API discovery and tool generation
- Authentication: API Key, Basic, OAuth2
- Connection pooling and lifecycle management
- Error recovery with retry logic
- Test configuration with integration test exclusion by default
- Advanced Search: Multiple algorithms with fuzzy matching and semantic search
- Monitoring and Metrics: Telemetry, PromEx, health checks, and performance monitoring
- 497+ tests with comprehensive coverage
- Production examples for all transports

#### Missing Features
- Batch Operations: Multiple tool calls

### Roadmap

#### Phase 1: Core Transports (Completed)
- [x] HTTP/HTTPS, CLI, WebSocket, gRPC, GraphQL, MCP

#### Phase 2: Enhanced Features (Completed)
- [x] OpenAPI Converter
- [x] TCP/UDP Transport
- [x] Advanced Search
- [x] Monitoring and Metrics

#### Phase 3: Extended Protocols (Completed)
- [x] WebRTC Transport

#### Phase 4: Enterprise Features
- [ ] Batch Operations
- [ ] Custom Variable Loaders
- [ ] API Documentation Generation

## Supported Transports

### Implemented
- HTTP/HTTPS: REST API integration with [OpenAPI](https://swagger.io/specification/) support
- CLI: Command-line tool integration
- [WebSocket](https://tools.ietf.org/html/rfc6455): Real-time communication
- [gRPC](https://grpc.io/): High-performance RPC calls with [Protocol Buffers](https://developers.google.com/protocol-buffers)
- [GraphQL](https://graphql.org/): GraphQL API integration with HTTP/HTTPS
- [MCP](https://modelcontextprotocol.io/): Model Context Protocol integration with [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [TCP/UDP](https://tools.ietf.org/html/rfc793): Low-level network protocols with connection management
- [WebRTC](https://www.w3.org/TR/webrtc/): Peer-to-peer communication with data channels and NAT traversal

### Planned
- Additional enterprise features and optimizations

## Examples

See `examples/` directory:
- `http_client.exs` - HTTP provider
- `cli_client.exs` - CLI provider
- `websocket_client.exs` - WebSocket provider
- `grpc_client.exs` - gRPC provider
- `graphql_example.exs` - GraphQL provider
- `mcp_example.exs` - MCP provider
- `tcp_udp_example.exs` - TCP/UDP provider
- `streaming_examples.exs` - Streaming examples
- `openapi_example.exs` - OpenAPI Converter examples
- `search_example.exs` - Advanced search examples
- `monitoring_example.exs` - Monitoring and metrics examples
- `webrtc_example.exs` - WebRTC peer-to-peer examples

## Testing

```bash
# Unit tests only (default - excludes integration tests)
mix test

# All tests including integration tests
mix test --include integration

# Integration tests only
mix test --only integration
```

The test suite is configured to exclude integration tests by default for faster development cycles. Integration tests require external services and are run separately.

## Advanced Search

ExUtcp provides sophisticated search capabilities for discovering tools and providers:

### Search Algorithms

- **Exact Search**: Precise matching for tool and provider names
- **Fuzzy Search**: Approximate matching using FuzzyCompare library for handling typos and variations
- **Semantic Search**: Intelligent matching using Haystack full-text search and keyword analysis
- **Combined Search**: Merges results from all algorithms for comprehensive discovery

### Search Features

- **Multi-field Search**: Search across tool names, descriptions, parameters, and responses
- **Advanced Filtering**: Filter by provider, transport type, tags, and capabilities
- **Result Ranking**: Intelligent scoring based on relevance, popularity, quality, and context
- **Security Scanning**: TruffleHog integration for detecting sensitive data in search results
- **Search Suggestions**: Auto-complete and suggestion system for improved user experience
- **Similar Tool Discovery**: Find related tools based on semantic similarity

### Basic Usage

```elixir
# Start client
{:ok, client} = ExUtcp.Client.start_link()

# Search with different algorithms
exact_results = ExUtcp.Client.search_tools(client, "get_user", %{algorithm: :exact})
fuzzy_results = ExUtcp.Client.search_tools(client, "get_usr", %{algorithm: :fuzzy, threshold: 0.6})
semantic_results = ExUtcp.Client.search_tools(client, "user management", %{algorithm: :semantic})

# Advanced search with filters and security scanning
advanced_results = ExUtcp.Client.search_tools(client, "api", %{
  algorithm: :combined,
  filters: %{transports: [:http, :websocket], providers: ["my_api"]},
  security_scan: true,
  filter_sensitive: true,
  limit: 10
})

# Get search suggestions
suggestions = ExUtcp.Client.get_search_suggestions(client, "us", limit: 5)

# Find similar tools
similar_tools = ExUtcp.Client.find_similar_tools(client, "get_user", limit: 3)
```

## Monitoring and Metrics

ExUtcp provides comprehensive monitoring capabilities for production deployments:

### Monitoring Features

- **Telemetry Integration**: Automatic telemetry events for all UTCP operations
- **Prometheus Metrics**: PromEx integration for metrics collection and visualization
- **Health Checks**: System health monitoring for transports and components
- **Performance Monitoring**: Operation timing, statistical analysis, and alerting
- **Custom Metrics**: Support for application-specific metrics and dashboards

### Telemetry Events

ExUtcp emits telemetry events for:
- Tool calls with duration, success/failure, and metadata
- Search operations with algorithm, filters, and result counts
- Provider registration and deregistration
- Connection establishment and lifecycle events
- System health and performance metrics

### Basic Usage

```elixir
# Start monitoring system
ExUtcp.Monitoring.start()

# Get system metrics
metrics = ExUtcp.Client.get_monitoring_metrics(client)

# Get health status
health = ExUtcp.Client.get_health_status(client)

# Get performance summary
performance = ExUtcp.Client.get_performance_summary(client)

# Record custom metrics
ExUtcp.Monitoring.Performance.record_custom_metric("api_requests", :counter, 1, %{endpoint: "/users"})
```

### Prometheus Integration

Configure PromEx in your application:

```elixir
# config/config.exs
config :ex_utcp, ExUtcp.Monitoring.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: "http://localhost:3000",
    username: "admin",
    password: "admin"
  ]
```

## Comparison with Python UTCP

ExUtcp is an independent Elixir implementation of the UTCP specification. For a detailed comparison with the official Python implementation, see our [Comparison Study](docs/COMPARISON_STUDY.md).

**Key Differences**:
- **ExUtcp**: 8 transports (includes WebSocket, gRPC, GraphQL, TCP/UDP, WebRTC)
- **Python UTCP**: 6 transports (HTTP, SSE, CLI, MCP, Text, Streamable HTTP)
- **ExUtcp**: Advanced search, monitoring, and health checks
- **Python UTCP**: Plugin architecture, official implementation

Both implementations follow the UTCP specification and excel in different areas.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Links

- [UTCP Website](https://www.utcp.io/)
- [Go Implementation](https://github.com/universal-tool-calling-protocol/go-utcp)
- [Python Implementation](https://github.com/universal-tool-calling-protocol/python-utcp)
- [Hex Package](https://hex.pm/packages/ex_utcp)
- [HexDocs](https://hexdocs.pm/ex_utcp)
