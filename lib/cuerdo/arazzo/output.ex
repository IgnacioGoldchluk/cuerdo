defmodule Cuerdo.Arazzo.Output do
  @moduledoc false
  alias Cuerdo.Arazzo.RuntimeExpression

  @schema Zoi.map(Zoi.string() |> Zoi.regex(~r/^[\w\.\-]+$/), RuntimeExpression.schema())
  def schema, do: @schema
end
