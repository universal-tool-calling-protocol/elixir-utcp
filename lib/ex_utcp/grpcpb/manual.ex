defmodule ExUtcp.Grpcpb.Manual do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:version, 1, type: :string)
  field(:tools, 2, repeated: true, type: ExUtcp.Grpcpb.Tool)
end
