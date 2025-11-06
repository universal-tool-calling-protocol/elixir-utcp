defmodule ExUtcp.Grpcpb.ToolCallRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:tool, 1, type: :string)
  field(:args_json, 2, type: :string)
end
