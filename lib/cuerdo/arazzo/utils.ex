defmodule Cuerdo.Arazzo.Utils do
  @moduledoc false
  alias Cuerdo.Arazzo.ReusableObject

  def linux_file_prefix, do: "file://"

  @compile {:inline, programming_friendly_id: 0}
  def programming_friendly_id, do: Zoi.string() |> Zoi.regex(~r/^[\w\-]+/)

  def or_reusable(schema), do: Zoi.union([schema, ReusableObject.schema()])

  def no_fragment(%URI{fragment: nil}), do: :ok

  def no_fragment(%URI{fragment: fragment}) when is_binary(fragment) do
    {:error, "cannot contain fragment"}
  end

  def cwd_as_uri do
    case File.cwd!() do
      "/" <> _ = path -> "#{linux_file_prefix()}#{path}/"
      path -> path
    end
  end

  def to_absolute_uri(self_uri) do
    # If we have a relative path then we should prepend with cwd_as_uri
    case URI.parse(self_uri) do
      %URI{scheme: nil} -> cwd_as_uri() |> URI.parse() |> URI.merge(self_uri)
      %URI{} = absolute_uri -> absolute_uri
    end
  end
end
