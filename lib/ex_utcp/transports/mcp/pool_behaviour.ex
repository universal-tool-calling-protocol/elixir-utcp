defmodule ExUtcp.Transports.Mcp.PoolBehaviour do
  @moduledoc """
  Behaviour for MCP connection pools to enable mocking in tests.
  """

  @callback get_connection(provider :: map()) :: {:ok, pid()} | {:error, term()}
  @callback close_connection(pid()) :: :ok
  @callback close_all_connections() :: :ok
  @callback stats() :: map()
end
