defmodule ExUtcp.Transports.Graphql.ConnectionBehaviour do
  @moduledoc """
  Behaviour for GraphQL connections to enable mocking in tests.
  """

  @callback start_link(provider :: map()) :: {:ok, pid()} | {:error, term()}
  @callback query(pid(), query :: String.t(), variables :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback mutation(pid(), mutation :: String.t(), variables :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback subscription(pid(), subscription :: String.t(), variables :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback introspect_schema(pid(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback close(pid()) :: :ok | {:error, term()}
  @callback get_last_used(pid()) :: integer()
  @callback update_last_used(pid()) :: :ok
end
