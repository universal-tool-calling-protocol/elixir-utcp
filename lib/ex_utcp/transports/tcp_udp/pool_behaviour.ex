defmodule ExUtcp.Transports.TcpUdp.PoolBehaviour do
  @moduledoc """
  Behaviour for TCP/UDP connection pools to enable mocking in tests.
  """

  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}
  @callback get_connection(pool_pid :: pid(), provider :: map()) ::
              {:ok, pid()} | {:error, term()}
  @callback close_connection(pool_pid :: pid(), conn_pid :: pid()) :: :ok | {:error, term()}
  @callback close_all_connections(pool_pid :: pid()) :: :ok | {:error, term()}
  @callback stats(pool_pid :: pid()) :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour ExUtcp.Transports.TcpUdp.PoolBehaviour
    end
  end
end
