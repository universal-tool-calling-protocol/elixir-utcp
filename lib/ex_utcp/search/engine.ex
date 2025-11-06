defmodule ExUtcp.Search.Engine do
  @moduledoc """
  Search engine for managing and indexing UTCP tools and providers.

  The engine maintains an in-memory index of tools and providers for fast searching.
  """

  use GenServer

  alias ExUtcp.Types

  @enforce_keys [:tools_index, :providers_index, :config]
  defstruct [:tools_index, :providers_index, :config]

  @type t :: %__MODULE__{
          tools_index: %{String.t() => Types.tool()},
          providers_index: %{String.t() => Types.provider_config()},
          config: map()
        }

  @doc """
  Creates a new search engine.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    config = %{
      fuzzy_threshold: Keyword.get(opts, :fuzzy_threshold, 0.6),
      semantic_threshold: Keyword.get(opts, :semantic_threshold, 0.3),
      max_results: Keyword.get(opts, :max_results, 100),
      enable_caching: Keyword.get(opts, :enable_caching, true)
    }

    %__MODULE__{
      tools_index: %{},
      providers_index: %{},
      config: config
    }
  end

  @doc """
  Starts the search engine as a GenServer.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a tool to the search index.
  """
  @spec add_tool(t() | pid(), Types.tool()) :: t() | :ok
  def add_tool(engine_or_pid, tool)

  def add_tool(%__MODULE__{} = engine, tool) do
    new_tools_index = Map.put(engine.tools_index, tool.name, tool)
    %{engine | tools_index: new_tools_index}
  end

  def add_tool(pid, tool) when is_pid(pid) do
    GenServer.call(pid, {:add_tool, tool})
  end

  @doc """
  Adds a provider to the search index.
  """
  @spec add_provider(t() | pid(), Types.provider_config()) :: t() | :ok
  def add_provider(engine_or_pid, provider)

  def add_provider(%__MODULE__{} = engine, provider) do
    new_providers_index = Map.put(engine.providers_index, provider.name, provider)
    %{engine | providers_index: new_providers_index}
  end

  def add_provider(pid, provider) when is_pid(pid) do
    GenServer.call(pid, {:add_provider, provider})
  end

  @doc """
  Removes a tool from the search index.
  """
  @spec remove_tool(t() | pid(), String.t()) :: t() | :ok
  def remove_tool(engine_or_pid, tool_name)

  def remove_tool(%__MODULE__{} = engine, tool_name) do
    new_tools_index = Map.delete(engine.tools_index, tool_name)
    %{engine | tools_index: new_tools_index}
  end

  def remove_tool(pid, tool_name) when is_pid(pid) do
    GenServer.call(pid, {:remove_tool, tool_name})
  end

  @doc """
  Removes a provider from the search index.
  """
  @spec remove_provider(t() | pid(), String.t()) :: t() | :ok
  def remove_provider(engine_or_pid, provider_name)

  def remove_provider(%__MODULE__{} = engine, provider_name) do
    new_providers_index = Map.delete(engine.providers_index, provider_name)
    %{engine | providers_index: new_providers_index}
  end

  def remove_provider(pid, provider_name) when is_pid(pid) do
    GenServer.call(pid, {:remove_provider, provider_name})
  end

  @doc """
  Gets all tools from the search index.
  """
  @spec get_all_tools(t() | pid()) :: [Types.tool()]
  def get_all_tools(engine_or_pid)

  def get_all_tools(%__MODULE__{} = engine) do
    Map.values(engine.tools_index)
  end

  def get_all_tools(pid) when is_pid(pid) do
    GenServer.call(pid, :get_all_tools)
  end

  @doc """
  Gets all providers from the search index.
  """
  @spec get_all_providers(t() | pid()) :: [Types.provider_config()]
  def get_all_providers(engine_or_pid)

  def get_all_providers(%__MODULE__{} = engine) do
    Map.values(engine.providers_index)
  end

  def get_all_providers(pid) when is_pid(pid) do
    GenServer.call(pid, :get_all_providers)
  end

  @doc """
  Gets a tool by name.
  """
  @spec get_tool(t() | pid(), String.t()) :: Types.tool() | nil
  def get_tool(engine_or_pid, tool_name)

  def get_tool(%__MODULE__{} = engine, tool_name) do
    Map.get(engine.tools_index, tool_name)
  end

  def get_tool(pid, tool_name) when is_pid(pid) do
    GenServer.call(pid, {:get_tool, tool_name})
  end

  @doc """
  Gets a provider by name.
  """
  @spec get_provider(t() | pid(), String.t()) :: Types.provider_config() | nil
  def get_provider(engine_or_pid, provider_name)

  def get_provider(%__MODULE__{} = engine, provider_name) do
    Map.get(engine.providers_index, provider_name)
  end

  def get_provider(pid, provider_name) when is_pid(pid) do
    GenServer.call(pid, {:get_provider, provider_name})
  end

  @doc """
  Clears all tools and providers from the search index.
  """
  @spec clear(t() | pid()) :: t() | :ok
  def clear(engine_or_pid)

  def clear(%__MODULE__{} = engine) do
    %{engine | tools_index: %{}, providers_index: %{}}
  end

  def clear(pid) when is_pid(pid) do
    GenServer.call(pid, :clear)
  end

  @doc """
  Gets search engine statistics.
  """
  @spec stats(t() | pid()) :: map()
  def stats(engine_or_pid)

  def stats(%__MODULE__{} = engine) do
    %{
      tools_count: map_size(engine.tools_index),
      providers_count: map_size(engine.providers_index),
      config: engine.config
    }
  end

  def stats(pid) when is_pid(pid) do
    GenServer.call(pid, :stats)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    engine = new(opts)
    {:ok, engine}
  end

  @impl GenServer
  def handle_call({:add_tool, tool}, _from, engine) do
    new_engine = add_tool(engine, tool)
    {:reply, :ok, new_engine}
  end

  @impl GenServer
  def handle_call({:add_provider, provider}, _from, engine) do
    new_engine = add_provider(engine, provider)
    {:reply, :ok, new_engine}
  end

  @impl GenServer
  def handle_call({:remove_tool, tool_name}, _from, engine) do
    new_engine = remove_tool(engine, tool_name)
    {:reply, :ok, new_engine}
  end

  @impl GenServer
  def handle_call({:remove_provider, provider_name}, _from, engine) do
    new_engine = remove_provider(engine, provider_name)
    {:reply, :ok, new_engine}
  end

  @impl GenServer
  def handle_call(:get_all_tools, _from, engine) do
    tools = get_all_tools(engine)
    {:reply, tools, engine}
  end

  @impl GenServer
  def handle_call(:get_all_providers, _from, engine) do
    providers = get_all_providers(engine)
    {:reply, providers, engine}
  end

  @impl GenServer
  def handle_call({:get_tool, tool_name}, _from, engine) do
    tool = get_tool(engine, tool_name)
    {:reply, tool, engine}
  end

  @impl GenServer
  def handle_call({:get_provider, provider_name}, _from, engine) do
    provider = get_provider(engine, provider_name)
    {:reply, provider, engine}
  end

  @impl GenServer
  def handle_call(:clear, _from, engine) do
    new_engine = clear(engine)
    {:reply, :ok, new_engine}
  end

  @impl GenServer
  def handle_call(:stats, _from, engine) do
    statistics = stats(engine)
    {:reply, statistics, engine}
  end
end
