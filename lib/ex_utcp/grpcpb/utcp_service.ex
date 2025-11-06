defmodule ExUtcp.Grpcpb.UTCPService do
  @moduledoc false
  use GRPC.Service, name: "grpcpb.UTCPService"

  rpc(:get_manual, ExUtcp.Grpcpb.Empty, ExUtcp.Grpcpb.Manual)
  rpc(:call_tool, ExUtcp.Grpcpb.ToolCallRequest, ExUtcp.Grpcpb.ToolCallResponse)
  rpc(:call_tool_stream, ExUtcp.Grpcpb.ToolCallRequest, stream(ExUtcp.Grpcpb.ToolCallResponse))
end

defmodule ExUtcp.Grpcpb.UTCPService.Stub do
  @moduledoc false
  use GRPC.Stub, service: ExUtcp.Grpcpb.UTCPService
end
