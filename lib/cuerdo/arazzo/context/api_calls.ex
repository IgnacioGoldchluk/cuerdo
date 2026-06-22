defmodule Cuerdo.Arazzo.Context.APICalls do
  @moduledoc """
  The request and response of each step
  """
  use Cuerdo.Object,
    schema: %{
      path: Zoi.list(Zoi.string(), min_length: 1),
      request: Zoi.struct(Req.Request),
      response: Zoi.struct(Req.Response)
    }
end
