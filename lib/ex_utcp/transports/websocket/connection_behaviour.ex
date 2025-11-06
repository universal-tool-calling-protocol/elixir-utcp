defmodule ExUtcp.Transports.WebSocket.ConnectionBehaviour do
  @moduledoc """
  Behaviour for WebSocket connections to enable mocking in tests.
  """

  @callback start_link(provider :: map()) :: {:ok, pid()} | {:error, term()}
  @callback call_tool(pid(), tool_name :: String.t(), args :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback call_tool_stream(pid(), tool_name :: String.t(), args :: map(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback close(pid()) :: :ok | {:error, term()}
  @callback get_last_used(pid()) :: integer()
  @callback update_last_used(pid()) :: :ok
end
