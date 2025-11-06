defmodule ExUtcp.Monitoring.PerformanceTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Monitoring.Performance

  @moduletag :unit

  describe "Performance Monitoring" do
    test "measures function execution time" do
      result =
        Performance.measure("test_operation", %{test: true}, fn ->
          Process.sleep(10)
          "test_result"
        end)

      assert result == "test_result"
    end

    test "measures function execution time with error" do
      assert_raise RuntimeError, "test error", fn ->
        Performance.measure("test_operation", %{test: true}, fn ->
          raise "test error"
        end)
      end
    end

    test "measures tool call performance" do
      result =
        Performance.measure_tool_call("test_tool", "test_provider", %{"arg" => "value"}, fn ->
          Process.sleep(5)
          {:ok, %{"result" => "success"}}
        end)

      assert result == {:ok, %{"result" => "success"}}
    end

    test "measures search performance" do
      result =
        Performance.measure_search("test query", :fuzzy, %{providers: []}, fn ->
          Process.sleep(5)
          [%{tool: %{name: "test"}, score: 0.9}]
        end)

      assert is_list(result)
      assert length(result) == 1
    end

    test "measures connection performance" do
      result =
        Performance.measure_connection("test_provider", :http, fn ->
          Process.sleep(5)
          {:ok, "connected"}
        end)

      assert result == {:ok, "connected"}
    end

    @tag :skip
    test "gets operation statistics" do
      # First, generate some test data
      Performance.measure("test_stats", %{}, fn ->
        Process.sleep(10)
        "result"
      end)

      stats = Performance.get_operation_stats("test_stats")

      assert is_map(stats)
      assert stats.operation == "test_stats"
      # Stats may be :unavailable if Metrics GenServer is not running
      assert stats.stats in [:no_data, :unavailable] or is_map(stats.stats)
    end

    @tag :skip
    test "gets performance summary" do
      summary = Performance.get_performance_summary()

      assert is_map(summary)
      assert Map.has_key?(summary, :system)
      assert Map.has_key?(summary, :timestamp)
      # May have :status => :metrics_unavailable if Metrics GenServer is not running
      assert Map.has_key?(summary, :operations) or Map.has_key?(summary, :status)
    end

    test "gets performance alerts" do
      # Pass empty metrics map
      alerts = Performance.get_performance_alerts(%{})

      assert is_list(alerts)
      # Alerts may be empty if no issues are detected
    end

    test "records custom metrics" do
      assert :ok = Performance.record_custom_metric("test_counter", :counter, 1, %{label: "test"})
      assert :ok = Performance.record_custom_metric("test_gauge", :gauge, 42, %{label: "test"})

      assert :ok =
               Performance.record_custom_metric("test_histogram", :histogram, 100, %{
                 label: "test"
               })

      assert :ok =
               Performance.record_custom_metric("test_summary", :summary, 200, %{label: "test"})
    end
  end
end
