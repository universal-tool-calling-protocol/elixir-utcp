defmodule ExUtcp.Transports.Mcp.MessageTest do
  use ExUnit.Case, async: true

  alias ExUtcp.Transports.Mcp.Message

  describe "MCP Message" do
    test "builds request message" do
      request = Message.build_request("tools/list", %{})

      assert request["jsonrpc"] == "2.0"
      assert request["method"] == "tools/list"
      assert request["params"] == %{}
      assert is_integer(request["id"])
    end

    test "builds request message with custom id" do
      request = Message.build_request("tools/list", %{}, 123)

      assert request["jsonrpc"] == "2.0"
      assert request["method"] == "tools/list"
      assert request["params"] == %{}
      assert request["id"] == 123
    end

    test "builds notification message" do
      notification = Message.build_notification("tools/update", %{name: "test"})

      assert notification["jsonrpc"] == "2.0"
      assert notification["method"] == "tools/update"
      assert notification["params"] == %{name: "test"}
      refute Map.has_key?(notification, "id")
    end

    test "builds response message" do
      response = Message.build_response(%{tools: []}, 123)

      assert response["jsonrpc"] == "2.0"
      assert response["result"] == %{tools: []}
      assert response["id"] == 123
    end

    test "builds error response message" do
      error = Message.build_error_response(-32_601, "Method not found", %{method: "invalid"}, 123)

      assert error["jsonrpc"] == "2.0"
      assert error["error"]["code"] == -32_601
      assert error["error"]["message"] == "Method not found"
      assert error["error"]["data"] == %{method: "invalid"}
      assert error["id"] == 123
    end

    test "parses valid JSON-RPC response" do
      json = ~s({"jsonrpc":"2.0","result":{"tools":[]},"id":123})

      assert {:ok, %{"tools" => []}} = Message.parse_response(json)
    end

    test "parses JSON-RPC error response" do
      json = ~s({"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":123})

      assert {:error, "JSON-RPC Error -32601: Method not found"} = Message.parse_response(json)
    end

    test "parses JSON-RPC request" do
      json = ~s({"jsonrpc":"2.0","method":"tools/list","params":{},"id":123})

      assert {:ok, %{"jsonrpc" => "2.0", "method" => "tools/list"}} = Message.parse_response(json)
    end

    test "validates valid message" do
      message = %{"jsonrpc" => "2.0", "method" => "test"}
      assert :ok = Message.validate_message(message)
    end

    test "validates message with missing jsonrpc" do
      message = %{"method" => "test"}
      assert {:error, "Missing jsonrpc field"} = Message.validate_message(message)
    end

    test "validates message with invalid jsonrpc version" do
      message = %{"jsonrpc" => "1.0", "method" => "test"}
      assert {:error, "Invalid jsonrpc version: 1.0"} = Message.validate_message(message)
    end

    test "extracts method from request" do
      message = %{"method" => "tools/list"}
      assert "tools/list" = Message.extract_method(message)
    end

    test "extracts id from message" do
      message = %{"id" => 123}
      assert 123 = Message.extract_id(message)
    end

    test "identifies notification" do
      notification = %{"method" => "test", "id" => nil}
      assert Message.notification?(notification)
    end

    test "identifies request" do
      request = %{"method" => "test", "id" => 123}
      assert Message.request?(request)
    end

    test "identifies response" do
      response = %{"result" => %{}}
      assert Message.response?(response)
    end

    test "identifies error response" do
      error = %{"error" => %{"code" => -1}}
      assert Message.error?(error)
    end

    test "extracts error information" do
      error = %{"error" => %{"code" => -32_601, "message" => "Method not found", "data" => %{}}}
      assert {-32_601, "Method not found", %{}} = Message.extract_error(error)
    end

    test "extracts result from response" do
      response = %{"result" => %{"tools" => []}}
      assert %{"tools" => []} = Message.extract_result(response)
    end
  end
end
