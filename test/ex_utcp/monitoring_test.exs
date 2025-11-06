defmodule ExUtcp.MonitoringTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Monitoring

  @moduletag :unit

  describe "Monitoring System" do
    test "starts and stops monitoring system" do
      assert :ok = Monitoring.start()
      assert :ok = Monitoring.stop()
    end

    test "emits tool call events" do
      # Test that telemetry events are emitted without errors
      assert :ok =
               Monitoring.emit_tool_call_event(
                 "test_tool",
                 "test_provider",
                 %{"arg1" => "value1"},
                 100,
                 :success,
                 %{"result" => "success"}
               )
    end

    test "emits search events" do
      assert :ok =
               Monitoring.emit_search_event(
                 "test query",
                 :fuzzy,
                 %{providers: ["test"]},
                 50,
                 5
               )
    end

    test "emits provider events" do
      assert :ok =
               Monitoring.emit_provider_event(
                 "test_provider",
                 :http,
                 :register,
                 3
               )
    end

    test "emits connection events" do
      assert :ok =
               Monitoring.emit_connection_event(
                 "test_provider",
                 :websocket,
                 :connect,
                 200
               )
    end

    test "gets system metrics" do
      metrics = Monitoring.get_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :system)
      assert Map.has_key?(metrics, :utcp)
      assert Map.has_key?(metrics, :timestamp)

      # Check system metrics structure
      system_metrics = metrics.system
      assert Map.has_key?(system_metrics, :memory)
      assert Map.has_key?(system_metrics, :processes)
      assert Map.has_key?(system_metrics, :schedulers)
    end

    test "gets health status" do
      health_status = Monitoring.get_health_status()

      assert is_map(health_status)
      assert Map.has_key?(health_status, :overall)
      assert Map.has_key?(health_status, :components)
      assert Map.has_key?(health_status, :timestamp)

      # Check components structure
      components = health_status.components
      assert Map.has_key?(components, :telemetry)
      assert Map.has_key?(components, :prometheus)
      assert Map.has_key?(components, :transports)
    end
  end
end
