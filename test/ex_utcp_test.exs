defmodule ExUtcpTest do
  use ExUnit.Case

  alias ExUtcp.Client
  alias ExUtcp.Config
  alias ExUtcp.Providers
  alias ExUtcp.Repository
  alias ExUtcp.Tools

  doctest ExUtcp

  describe "Config" do
    test "creates default configuration" do
      config = Config.new()

      assert config.variables == %{}
      assert config.providers_file_path == nil
      assert config.load_variables_from == []
    end

    test "creates configuration with options" do
      config =
        Config.new(
          variables: %{"API_KEY" => "test123"},
          providers_file_path: "test.json"
        )

      assert config.variables == %{"API_KEY" => "test123"}
      assert config.providers_file_path == "test.json"
    end

    test "substitutes variables in strings" do
      config = Config.new(variables: %{"API_KEY" => "test123"})

      result = Config.substitute_variables(config, "Bearer ${API_KEY}")
      assert result == "Bearer test123"
    end

    test "substitutes variables in maps" do
      config = Config.new(variables: %{"API_KEY" => "test123"})

      input = %{"url" => "https://api.example.com?key=${API_KEY}"}
      result = Config.substitute_variables(config, input)

      assert result == %{"url" => "https://api.example.com?key=test123"}
    end
  end

  describe "Tools" do
    test "creates a new tool" do
      provider = Providers.new_http_provider(name: "test", url: "http://example.com")

      tool =
        Tools.new_tool(
          name: "test_tool",
          description: "A test tool",
          provider: provider
        )

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
      assert tool.provider == provider
    end

    test "validates tool" do
      tool = Tools.new_tool(name: "", provider: nil)

      assert {:error, "Tool name is required"} = Tools.validate_tool(tool)
    end

    test "matches query" do
      tool =
        Tools.new_tool(
          name: "test_tool",
          description: "A test tool",
          tags: ["test", "example"],
          provider: %{}
        )

      assert Tools.matches_query?(tool, "test")
      assert Tools.matches_query?(tool, "tool")
      assert Tools.matches_query?(tool, "example")
      refute Tools.matches_query?(tool, "nonexistent")
    end

    test "normalizes tool name" do
      assert Tools.normalize_name("tool_name", "provider") == "provider.tool_name"
      assert Tools.normalize_name("provider.tool_name", "provider") == "provider.tool_name"
      assert Tools.normalize_name("other.tool_name", "provider") == "provider.tool_name"
    end

    test "extracts tool and provider names" do
      assert Tools.extract_tool_name("provider.tool_name") == "tool_name"
      assert Tools.extract_provider_name("provider.tool_name") == "provider"
    end
  end

  describe "Providers" do
    test "creates HTTP provider" do
      provider =
        Providers.new_http_provider(
          name: "test",
          url: "http://example.com"
        )

      assert provider.name == "test"
      assert provider.type == :http
      assert provider.url == "http://example.com"
    end

    test "creates CLI provider" do
      provider =
        Providers.new_cli_provider(
          name: "test",
          command_name: "echo hello"
        )

      assert provider.name == "test"
      assert provider.type == :cli
      assert provider.command_name == "echo hello"
    end

    test "creates WebSocket provider" do
      provider =
        Providers.new_websocket_provider(
          name: "test",
          url: "ws://example.com/ws"
        )

      assert provider.name == "test"
      assert provider.type == :websocket
      assert provider.url == "ws://example.com/ws"
      assert provider.protocol == nil
      assert provider.keep_alive == false
    end

    test "creates gRPC provider" do
      provider =
        Providers.new_grpc_provider(
          name: "test",
          host: "localhost",
          port: 9339
        )

      assert provider.name == "test"
      assert provider.type == :grpc
      assert provider.host == "localhost"
      assert provider.port == 9339
      assert provider.service_name == "UTCPService"
      assert provider.method_name == "CallTool"
      assert provider.use_ssl == false
    end

    test "validates provider" do
      provider = %{name: "", type: :http}

      assert {:error, "Provider name is required"} = Providers.validate_provider(provider)
    end

    test "normalizes provider name" do
      assert Providers.normalize_name("test.provider") == "test_provider"
    end
  end

  describe "Repository" do
    test "creates new repository" do
      repo = Repository.new()

      assert repo.tools == %{}
      assert repo.providers == %{}
    end

    test "saves provider with tools" do
      repo = Repository.new()
      provider = Providers.new_http_provider(name: "test", url: "http://example.com")
      tool = Tools.new_tool(name: "test_tool", provider: provider)

      updated_repo = Repository.save_provider_with_tools(repo, provider, [tool])

      assert Repository.get_provider(updated_repo, "test") == provider
      assert Repository.get_tools_by_provider(updated_repo, "test") == [tool]
    end

    test "searches tools" do
      repo = Repository.new()
      provider = Providers.new_http_provider(name: "test", url: "http://example.com")
      tool = Tools.new_tool(name: "test_tool", description: "A test tool", provider: provider)

      updated_repo = Repository.save_provider_with_tools(repo, provider, [tool])

      results = Repository.search_tools(updated_repo, "test", 10)
      assert length(results) == 1
      assert List.first(results).name == "test_tool"
    end

    test "removes provider" do
      repo = Repository.new()
      provider = Providers.new_http_provider(name: "test", url: "http://example.com")
      tool = Tools.new_tool(name: "test_tool", provider: provider)

      updated_repo = Repository.save_provider_with_tools(repo, provider, [tool])
      final_repo = Repository.remove_provider(updated_repo, "test")

      assert Repository.get_provider(final_repo, "test") == nil
      assert Repository.get_tools_by_provider(final_repo, "test") == []
    end
  end

  describe "Client" do
    test "starts client with configuration" do
      config = Config.new()
      {:ok, client} = Client.start_link(config)

      assert is_pid(client)

      # Clean up
      GenServer.stop(client)
    end

    test "gets client statistics" do
      config = Config.new()
      {:ok, client} = Client.start_link(config)

      stats = Client.get_stats(client)

      assert is_map(stats)
      assert Map.has_key?(stats, :tool_count)
      assert Map.has_key?(stats, :provider_count)

      # Clean up
      GenServer.stop(client)
    end

    test "searches tools" do
      config = Config.new()
      {:ok, client} = Client.start_link(config)

      results = Client.search_tools(client, "", %{limit: 10})
      assert is_list(results)

      # Clean up
      GenServer.stop(client)
    end
  end
end
