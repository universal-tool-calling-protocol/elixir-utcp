defmodule ExUtcp.Transports.Graphql.PoolBehaviour do
  @moduledoc """
  Behaviour for GraphQL connection pools to enable mocking in tests.
  """

  @callback get_connection(provider :: map()) :: {:ok, pid()} | {:error, term()}
  @callback return_connection(pid()) :: :ok
  @callback close_connection(pid()) :: :ok
  @callback close_all_connections() :: :ok
  @callback stats() :: map()
end
