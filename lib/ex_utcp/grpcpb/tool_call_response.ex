defmodule ExUtcp.Grpcpb.ToolCallResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:result_json, 1, type: :string)
end
