defmodule ExUtcp.Transports.Mcp.ConnectionBehaviour do
  @moduledoc """
  Behaviour for MCP connections to enable mocking in tests.
  """

  @callback start_link(provider :: map(), opts :: keyword()) :: {:ok, pid()} | {:error, term()}
  @callback call_tool(pid(), tool_name :: String.t(), args :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback call_tool_stream(pid(), tool_name :: String.t(), args :: map(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback send_request(pid(), method :: String.t(), params :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback send_notification(pid(), method :: String.t(), params :: map(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback close(pid()) :: :ok | {:error, term()}
  @callback get_last_used(pid()) :: integer()
  @callback update_last_used(pid()) :: :ok
end
