defmodule ExUtcp.Transports.TcpUdp.ConnectionBehaviour do
  @moduledoc """
  Behaviour for TCP/UDP connections to enable mocking in tests.
  """

  @callback start_link(provider :: map()) :: {:ok, pid()} | {:error, term()}
  @callback call_tool(conn :: pid(), tool_name :: String.t(), args :: map(), timeout :: integer()) ::
              {:ok, any()} | {:error, term()}
  @callback call_tool_stream(
              conn :: pid(),
              tool_name :: String.t(),
              args :: map(),
              timeout :: integer()
            ) :: {:ok, Enumerable.t()} | {:error, term()}
  @callback close(conn :: pid()) :: :ok | {:error, term()}
  @callback get_last_used(conn :: pid()) :: integer()
  @callback update_last_used(conn :: pid()) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour ExUtcp.Transports.TcpUdp.ConnectionBehaviour
    end
  end
end
