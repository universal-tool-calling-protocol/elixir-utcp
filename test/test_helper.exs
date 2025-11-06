# Exclude integration tests by default
# To run integration tests: mix test --include integration
ExUnit.start(exclude: [:integration])

# Configure Mox
Mox.defmock(ExUtcp.Transports.Graphql.ConnectionMock,
  for: ExUtcp.Transports.Graphql.ConnectionBehaviour
)

Mox.defmock(ExUtcp.Transports.Graphql.PoolMock, for: ExUtcp.Transports.Graphql.PoolBehaviour)

Mox.defmock(ExUtcp.Transports.Grpc.ConnectionMock,
  for: ExUtcp.Transports.Grpc.ConnectionBehaviour
)

Mox.defmock(ExUtcp.Transports.Grpc.PoolMock, for: ExUtcp.Transports.Grpc.PoolBehaviour)

Mox.defmock(ExUtcp.Transports.WebSocket.ConnectionMock,
  for: ExUtcp.Transports.WebSocket.ConnectionBehaviour
)

Mox.defmock(ExUtcp.Transports.Mcp.ConnectionMock, for: ExUtcp.Transports.Mcp.ConnectionBehaviour)
Mox.defmock(ExUtcp.Transports.Mcp.PoolMock, for: ExUtcp.Transports.Mcp.PoolBehaviour)
