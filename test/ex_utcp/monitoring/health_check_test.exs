defmodule ExUtcp.Monitoring.HealthCheckTest do
  use ExUnit.Case, async: false

  alias ExUtcp.Monitoring.HealthCheck

  @moduletag :unit

  describe "Health Check System" do
    test "starts and provides health status" do
      {:ok, pid} = HealthCheck.start_link()

      # Give it a moment to initialize
      Process.sleep(100)

      health_status = HealthCheck.get_health_status()

      assert is_map(health_status)
      assert Map.has_key?(health_status, :status)
      assert Map.has_key?(health_status, :checks)
      assert Map.has_key?(health_status, :timestamp)

      GenServer.stop(pid)
    end

    test "runs health checks on demand" do
      {:ok, pid} = HealthCheck.start_link()

      health_results = HealthCheck.run_health_checks()

      assert is_map(health_results)
      assert Map.has_key?(health_results, :status)
      assert Map.has_key?(health_results, :checks)

      GenServer.stop(pid)
    end

    test "registers and unregisters custom checks" do
      {:ok, pid} = HealthCheck.start_link()

      # Register a custom check
      custom_check = fn ->
        %{
          status: :healthy,
          message: "Custom check passed"
        }
      end

      assert :ok = HealthCheck.register_check("custom_test", custom_check)

      # Run health checks to see the custom check
      health_results = HealthCheck.run_health_checks()
      assert Map.has_key?(health_results.checks, "custom_test")

      # Unregister the check
      assert :ok = HealthCheck.unregister_check("custom_test")

      # Verify it's removed
      health_results = HealthCheck.run_health_checks()
      refute Map.has_key?(health_results.checks, "custom_test")

      GenServer.stop(pid)
    end

    test "handles failing health checks" do
      {:ok, pid} = HealthCheck.start_link()

      # Register a failing check
      failing_check = fn ->
        raise "Simulated failure"
      end

      assert :ok = HealthCheck.register_check("failing_test", failing_check)

      # Run health checks
      health_results = HealthCheck.run_health_checks()

      # Should have the failing check with unhealthy status
      failing_result = health_results.checks["failing_test"]
      assert failing_result != nil
      assert failing_result.status == :unhealthy
      assert String.contains?(failing_result.message, "Health check failed")

      GenServer.stop(pid)
    end
  end
end
