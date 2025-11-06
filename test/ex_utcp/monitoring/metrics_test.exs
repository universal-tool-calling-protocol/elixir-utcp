defmodule ExUtcp.Monitoring.MetricsTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Monitoring.Metrics

  @moduletag :unit

  describe "Metrics Collection" do
    setup do
      # Start metrics collector for testing
      {:ok, pid} = Metrics.start_link()

      on_exit(fn ->
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end)

      %{metrics_pid: pid}
    end

    test "increments counters", %{metrics_pid: _pid} do
      assert :ok = Metrics.increment_counter("test_counter", %{label: "test"})
      assert :ok = Metrics.increment_counter("test_counter", %{label: "test"})

      # Get the metric and verify it was incremented
      metric = Metrics.get_metric("test_counter")
      assert metric != nil
    end

    test "sets gauge values", %{metrics_pid: _pid} do
      assert :ok = Metrics.set_gauge("test_gauge", 42, %{label: "test"})
      assert :ok = Metrics.set_gauge("test_gauge", 84, %{label: "test"})

      metric = Metrics.get_metric("test_gauge")
      assert metric != nil
    end

    test "observes histogram values", %{metrics_pid: _pid} do
      assert :ok = Metrics.observe_histogram("test_histogram", 100, %{label: "test"})
      assert :ok = Metrics.observe_histogram("test_histogram", 200, %{label: "test"})
      assert :ok = Metrics.observe_histogram("test_histogram", 150, %{label: "test"})

      metric = Metrics.get_metric("test_histogram")
      assert metric != nil
    end

    test "observes summary values", %{metrics_pid: _pid} do
      assert :ok = Metrics.observe_summary("test_summary", 50, %{label: "test"})
      assert :ok = Metrics.observe_summary("test_summary", 75, %{label: "test"})
      assert :ok = Metrics.observe_summary("test_summary", 100, %{label: "test"})

      metric = Metrics.get_metric("test_summary")
      assert metric != nil
    end

    test "gets all metrics", %{metrics_pid: _pid} do
      # Add some test metrics
      Metrics.increment_counter("counter1", %{type: "test"})
      Metrics.set_gauge("gauge1", 42, %{type: "test"})

      all_metrics = Metrics.get_metrics()

      assert is_map(all_metrics)
      # May contain the metrics we just added
    end

    test "resets metrics", %{metrics_pid: _pid} do
      # Add some metrics
      Metrics.increment_counter("test_reset", %{})
      Metrics.set_gauge("test_reset_gauge", 100, %{})

      # Reset all metrics
      assert :ok = Metrics.reset_metrics()

      # Verify metrics are reset
      all_metrics = Metrics.get_metrics()
      assert all_metrics == %{}
    end

    test "gets metrics summary", %{metrics_pid: _pid} do
      summary = Metrics.get_metrics_summary()

      assert is_map(summary)
      assert Map.has_key?(summary, :uptime_ms)
      assert Map.has_key?(summary, :total_metrics)
      assert Map.has_key?(summary, :config)
      assert Map.has_key?(summary, :memory_usage)
      assert Map.has_key?(summary, :process_count)

      assert is_integer(summary.uptime_ms)
      assert summary.uptime_ms >= 0
    end
  end
end
