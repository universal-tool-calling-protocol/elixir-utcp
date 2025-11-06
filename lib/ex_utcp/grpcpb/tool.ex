defmodule ExUtcp.Grpcpb.Tool do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:name, 1, type: :string)
  field(:description, 2, type: :string)
  field(:inputs, 3, type: :string)
  field(:outputs, 4, type: :string)
  field(:tags, 5, repeated: true, type: :string)
end
