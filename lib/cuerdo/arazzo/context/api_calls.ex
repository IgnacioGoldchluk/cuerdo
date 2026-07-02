defmodule Cuerdo.Arazzo.Context.APICalls do
  @moduledoc """
  The request and response of each step
  """
  use Cuerdo.Object,
    schema: %{
      path: Zoi.list(Zoi.string(), min_length: 1),
      request: Zoi.struct(Req.Request),
      response: Zoi.struct(Req.Response),
      time_ms: Zoi.integer(gte: 0)
    }

  @type t :: %__MODULE__{
          path: [String.t()],
          request: Req.Request.t(),
          response: Req.Response.t(),
          time_ms: non_neg_integer()
        }
end
