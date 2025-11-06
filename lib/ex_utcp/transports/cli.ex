defmodule ExUtcp.Transports.Cli do
  @moduledoc """
  CLI transport implementation for UTCP.

  This transport handles command-line based tool providers, executing external
  commands to discover and call tools.
  """

  use ExUtcp.Transports.Behaviour

  defstruct [
    :logger
  ]

  @doc """
  Creates a new CLI transport.
  """
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts \\ []) do
    %__MODULE__{
      logger: Keyword.get(opts, :logger, &IO.puts/1)
    }
  end

  @impl ExUtcp.Transports.Behaviour
  def register_tool_provider(provider) do
    case provider.type do
      :cli -> discover_tools(provider)
      _ -> {:error, "CLI transport can only be used with CLI providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def deregister_tool_provider(_provider) do
    :ok
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool(tool_name, args, provider) do
    case provider.type do
      :cli -> execute_tool_call(tool_name, args, provider)
      _ -> {:error, "CLI transport can only be used with CLI providers"}
    end
  end

  @impl ExUtcp.Transports.Behaviour
  def call_tool_stream(_tool_name, _args, _provider) do
    {:error, "Streaming not supported by CLI transport"}
  end

  @impl ExUtcp.Transports.Behaviour
  def close do
    :ok
  end

  @impl ExUtcp.Transports.Behaviour
  def transport_name do
    "cli"
  end

  @impl ExUtcp.Transports.Behaviour
  def supports_streaming? do
    false
  end

  # Private functions

  defp discover_tools(provider) do
    with {:ok, output} <- execute_discovery_command(provider) do
      parse_discovery_output(output, provider)
    end
  end

  defp execute_tool_call(tool_name, args, provider) do
    with {:ok, output} <- execute_tool_command(tool_name, args, provider) do
      parse_tool_output(output)
    end
  end

  defp execute_discovery_command(provider) do
    command_parts = String.split(provider.command_name, " ", trim: true)
    [cmd_path | cmd_args] = command_parts

    env = prepare_environment(provider)
    working_dir = provider.working_dir

    cmd_opts = [
      env: env,
      stderr_to_stdout: true
    ]

    cmd_opts = if working_dir, do: [{:cd, working_dir} | cmd_opts], else: cmd_opts

    case System.cmd(cmd_path, cmd_args, cmd_opts) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, "Command failed with exit code #{exit_code}: #{output}"}
    end
  end

  defp execute_tool_command(tool_name, args, provider) do
    command_parts = String.split(provider.command_name, " ", trim: true)
    [cmd_path | _] = command_parts

    # Build command args: call <provider> <tool> [--flags]
    cmd_args = ["call", provider.name, tool_name] ++ format_arguments(args)

    env = prepare_environment(provider)
    working_dir = provider.working_dir

    # Prepare JSON payload for stdin
    input =
      case Jason.encode(args) do
        {:ok, json} -> json
        {:error, _} -> ""
      end

    cmd_opts = [
      env: env,
      input: input,
      stderr_to_stdout: true
    ]

    cmd_opts = if working_dir, do: [{:cd, working_dir} | cmd_opts], else: cmd_opts

    case System.cmd(cmd_path, cmd_args, cmd_opts) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, "Command failed with exit code #{exit_code}: #{output}"}
    end
  end

  defp prepare_environment(provider) do
    base_env = System.get_env()
    Map.merge(base_env, provider.env_vars)
  end

  defp format_arguments(args) do
    args
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.flat_map(fn {key, value} -> format_argument(key, value) end)
  end

  defp format_argument(key, value) do
    case value do
      true ->
        ["--#{key}"]

      false ->
        []

      values when is_list(values) ->
        Enum.flat_map(values, fn v -> ["--#{key}", to_string(v)] end)

      _ ->
        ["--#{key}", to_string(value)]
    end
  end

  defp parse_discovery_output(output, provider) do
    output = String.trim(output)

    # Remove surrounding quotes if present
    output =
      if String.starts_with?(output, "'") and String.ends_with?(output, "'") do
        String.slice(output, 1..-2//1)
      else
        output
      end

    cond do
      output == "" ->
        {:ok, []}

      String.starts_with?(output, "{") and String.ends_with?(output, "}") ->
        parse_utcp_manual(output, provider)

      true ->
        parse_line_by_line(output, provider)
    end
  end

  defp parse_tool_output(output) do
    output = String.trim(output)

    cond do
      output == "" ->
        {:ok, ""}

      String.starts_with?(output, "{") and String.ends_with?(output, "}") ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:ok, output}
        end

      true ->
        {:ok, output}
    end
  end

  defp parse_utcp_manual(output, provider) do
    case Jason.decode(output) do
      {:ok, data} ->
        case data do
          %{"tools" => tools} when is_list(tools) ->
            normalized_tools = Enum.map(tools, &normalize_tool(&1, provider))
            {:ok, normalized_tools}

          %{"name" => _} ->
            # Single tool
            normalized_tool = normalize_tool(data, provider)
            {:ok, [normalized_tool]}

          _ ->
            {:ok, []}
        end

      {:error, _reason} ->
        {:ok, []}
    end
  end

  defp parse_line_by_line(output, provider) do
    tools =
      output
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> Enum.filter(&String.ends_with?(&1, "}"))
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, data} -> [normalize_tool(data, provider)]
          {:error, _} -> []
        end
      end)

    {:ok, tools}
  end

  defp normalize_tool(tool_data, provider) do
    ExUtcp.Tools.new_tool(
      name: Map.get(tool_data, "name", ""),
      description: Map.get(tool_data, "description", ""),
      inputs: parse_schema(Map.get(tool_data, "inputs", %{})),
      outputs: parse_schema(Map.get(tool_data, "outputs", %{})),
      tags: Map.get(tool_data, "tags", []),
      average_response_size: Map.get(tool_data, "average_response_size"),
      provider: provider
    )
  end

  defp parse_schema(schema_data) do
    ExUtcp.Tools.new_schema(
      type: Map.get(schema_data, "type", "object"),
      properties: Map.get(schema_data, "properties", %{}),
      required: Map.get(schema_data, "required", []),
      description: Map.get(schema_data, "description", ""),
      title: Map.get(schema_data, "title", ""),
      items: Map.get(schema_data, "items", %{}),
      enum: Map.get(schema_data, "enum", []),
      minimum: Map.get(schema_data, "minimum"),
      maximum: Map.get(schema_data, "maximum"),
      format: Map.get(schema_data, "format", "")
    )
  end
end
