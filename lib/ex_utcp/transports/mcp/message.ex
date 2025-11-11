defmodule ExUtcp.Transports.Mcp.Message do
  @moduledoc """
  Handles JSON-RPC 2.0 message formatting and parsing for MCP protocol.
  """

  require Logger

  @doc """
  Builds a JSON-RPC 2.0 request message.
  """
  @spec build_request(String.t(), map(), integer() | nil) :: map()
  def build_request(method, params, id \\ nil) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id || generate_request_id()
    }
  end

  @doc """
  Builds a JSON-RPC 2.0 notification message.
  """
  @spec build_notification(String.t(), map()) :: map()
  def build_notification(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
  end

  @doc """
  Builds a JSON-RPC 2.0 response message.
  """
  @spec build_response(any(), integer() | nil) :: map()
  def build_response(result, id) do
    %{
      "jsonrpc" => "2.0",
      "result" => result,
      "id" => id
    }
  end

  @doc """
  Builds a JSON-RPC 2.0 error response message.
  """
  @spec build_error_response(integer(), String.t(), any(), integer() | nil) :: map()
  def build_error_response(code, message, data \\ nil, id \\ nil) do
    error = %{
      "code" => code,
      "message" => message
    }

    error = if data, do: Map.put(error, "data", data), else: error

    %{
      "jsonrpc" => "2.0",
      "error" => error,
      "id" => id
    }
  end

  @doc """
  Parses a JSON-RPC 2.0 response.
  """
  @spec parse_response(String.t()) :: {:ok, any()} | {:error, String.t()}
  def parse_response(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"jsonrpc" => "2.0"} = message} ->
        parse_jsonrpc_message(message)

      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        {:error, "Failed to parse JSON: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates a JSON-RPC 2.0 message.
  """
  @spec validate_message(map()) :: :ok | {:error, String.t()}
  def validate_message(message) do
    cond do
      not Map.has_key?(message, "jsonrpc") ->
        {:error, "Missing jsonrpc field"}

      message["jsonrpc"] != "2.0" ->
        {:error, "Invalid jsonrpc version: #{message["jsonrpc"]}"}

      not Map.has_key?(message, "method") and not Map.has_key?(message, "result") and
          not Map.has_key?(message, "error") ->
        {:error, "Message must have method, result, or error field"}

      true ->
        :ok
    end
  end

  @doc """
  Extracts the method name from a request message.
  """
  @spec extract_method(map()) :: String.t() | nil
  def extract_method(%{"method" => method}), do: method
  def extract_method(_), do: nil

  @doc """
  Extracts the request ID from a message.
  """
  @spec extract_id(map()) :: integer() | nil
  def extract_id(%{"id" => id}), do: id
  def extract_id(_), do: nil

  @doc """
  Checks if a message is a notification.
  """
  @spec notification?(map()) :: boolean()
  def notification?(%{"method" => _method, "id" => nil}), do: true
  def notification?(%{"method" => _method}), do: false
  def notification?(_), do: false

  @doc """
  Checks if a message is a request.
  """
  @spec request?(map()) :: boolean()
  def request?(%{"method" => _method, "id" => id}) when not is_nil(id), do: true
  def request?(_), do: false

  @doc """
  Checks if a message is a response.
  """
  @spec response?(map()) :: boolean()
  def response?(%{"result" => _result}), do: true
  def response?(%{"error" => _error}), do: true
  def response?(_), do: false

  @doc """
  Checks if a message is an error response.
  """
  @spec error?(map()) :: boolean()
  def error?(%{"error" => _error}), do: true
  def error?(_), do: false

  @doc """
  Extracts error information from an error response.
  """
  @spec extract_error(map()) :: {integer(), String.t(), any()}
  def extract_error(%{"error" => error}) do
    code = Map.get(error, "code", -1)
    message = Map.get(error, "message", "Unknown error")
    data = Map.get(error, "data")
    {code, message, data}
  end

  @doc """
  Extracts result from a successful response.
  """
  @spec extract_result(map()) :: any()
  def extract_result(%{"result" => result}), do: result
  def extract_result(_), do: nil

  # Private functions

  defp parse_jsonrpc_message(%{"result" => result} = message) do
    case validate_message(message) do
      :ok -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_jsonrpc_message(%{"error" => _error} = message) do
    case validate_message(message) do
      :ok ->
        {code, message_text, data} = extract_error(message)

        {:error, "JSON-RPC Error #{code}: #{message_text}#{if data, do: " (#{inspect(data)})", else: ""}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_jsonrpc_message(%{"method" => _method} = message) do
    case validate_message(message) do
      :ok -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_jsonrpc_message(message) do
    case validate_message(message) do
      :ok -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_request_id do
    :rand.uniform(1_000_000)
  end
end
