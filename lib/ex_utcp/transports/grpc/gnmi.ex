defmodule ExUtcp.Transports.Grpc.Gnmi do
  @moduledoc """
  gNMI (gRPC Network Management Interface) specific functionality.

  This module provides specialized functions for network management operations
  using the gNMI protocol over gRPC.
  """

  require Logger

  @doc """
  Performs a gNMI Get operation to retrieve configuration or state data.
  """
  @spec get(pid(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def get(connection_pid, paths, opts \\ []) do
    request = build_get_request(paths, opts)
    call_gnmi_operation(connection_pid, :get, request, opts)
  end

  @doc """
  Performs a gNMI Set operation to modify configuration.
  """
  @spec set(pid(), [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def set(connection_pid, updates, opts \\ []) do
    request = build_set_request(updates, opts)
    call_gnmi_operation(connection_pid, :set, request, opts)
  end

  @doc """
  Performs a gNMI Subscribe operation for real-time data streaming.
  """
  @spec subscribe(pid(), [String.t()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def subscribe(connection_pid, paths, opts \\ []) do
    request = build_subscribe_request(paths, opts)
    call_gnmi_operation(connection_pid, :subscribe, request, opts)
  end

  @doc """
  Performs a gNMI Capabilities operation to discover supported models.
  """
  @spec capabilities(pid(), keyword()) :: {:ok, map()} | {:error, term()}
  def capabilities(connection_pid, opts \\ []) do
    request = build_capabilities_request()
    call_gnmi_operation(connection_pid, :capabilities, request, opts)
  end

  @doc """
  Validates gNMI paths for correctness.
  """
  @spec validate_paths([String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  def validate_paths(paths) when is_list(paths) do
    validated_paths =
      paths
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&normalize_path/1)

    if Enum.empty?(validated_paths) do
      {:error, "No valid paths provided"}
    else
      {:ok, validated_paths}
    end
  end

  @doc """
  Builds a gNMI path from components.
  """
  @spec build_path(String.t(), [String.t()], String.t()) :: String.t()
  def build_path(origin, elements, target \\ "") do
    path_parts = [origin | elements]
    path = Enum.join(path_parts, "/")

    if target == "" do
      path
    else
      "#{path}[#{target}]"
    end
  end

  @doc """
  Parses a gNMI path into components.
  """
  @spec parse_path(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_path(path) do
    # Simple path parsing - in a real implementation, this would be more sophisticated
    parts = String.split(path, "/", trim: true)

    case parts do
      [origin | elements] ->
        {:ok,
         %{
           origin: origin,
           elements: elements,
           full_path: path
         }}

      [] ->
        {:error, "Empty path"}
    end
  rescue
    error ->
      {:error, "Failed to parse path: #{inspect(error)}"}
  end

  # Private functions

  defp build_get_request(paths, opts) do
    %{
      "type" => "GetRequest",
      "path" => Enum.map(paths, &%{"elem" => String.split(&1, "/", trim: true)}),
      "encoding" => Keyword.get(opts, :encoding, "JSON"),
      "use_models" => Keyword.get(opts, :use_models, []),
      "extension" => Keyword.get(opts, :extension, [])
    }
  end

  defp build_set_request(updates, opts) do
    %{
      "type" => "SetRequest",
      "replace" => Keyword.get(opts, :replace, []),
      "update" => updates,
      "delete" => Keyword.get(opts, :delete, []),
      "extension" => Keyword.get(opts, :extension, [])
    }
  end

  defp build_subscribe_request(paths, opts) do
    subscription_list =
      Enum.map(paths, fn path ->
        %{
          "path" => %{"elem" => String.split(path, "/", trim: true)},
          "mode" => Keyword.get(opts, :mode, "ON_CHANGE"),
          "sample_interval" => Keyword.get(opts, :sample_interval, 0),
          "suppress_redundant" => Keyword.get(opts, :suppress_redundant, false),
          "heartbeat_interval" => Keyword.get(opts, :heartbeat_interval, 0)
        }
      end)

    %{
      "type" => "SubscribeRequest",
      "subscribe" => %{
        "subscription" => subscription_list,
        "mode" => Keyword.get(opts, :subscribe_mode, "STREAM"),
        "use_models" => Keyword.get(opts, :use_models, []),
        "qos" => Keyword.get(opts, :qos, %{}),
        "encoding" => Keyword.get(opts, :encoding, "JSON"),
        "updates_only" => Keyword.get(opts, :updates_only, false)
      }
    }
  end

  defp build_capabilities_request do
    %{
      "type" => "CapabilityRequest"
    }
  end

  defp call_gnmi_operation(connection_pid, operation, request, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    # For now, we'll use the standard gRPC connection to call the gNMI operation
    # In a real implementation, this would use a dedicated gNMI service
    case operation do
      :get ->
        ExUtcp.Transports.Grpc.Connection.call_tool(connection_pid, "gnmi.get", request, timeout)

      :set ->
        ExUtcp.Transports.Grpc.Connection.call_tool(connection_pid, "gnmi.set", request, timeout)

      :subscribe ->
        ExUtcp.Transports.Grpc.Connection.call_tool_stream(
          connection_pid,
          "gnmi.subscribe",
          request,
          timeout
        )

      :capabilities ->
        ExUtcp.Transports.Grpc.Connection.call_tool(
          connection_pid,
          "gnmi.capabilities",
          request,
          timeout
        )
    end
  end

  defp normalize_path(path) do
    path
    |> String.trim()
    # Replace multiple slashes with single slash
    |> String.replace(~r/\/+/, "/")
    # Remove leading slash
    |> String.replace_leading("/", "")
  end
end
