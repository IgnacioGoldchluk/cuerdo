defmodule Cuerdo.Arazzo.Replacement do
  @moduledoc """
  An Arazzo Payload [Replacement Object](https://spec.openapis.org/arazzo/v1.0.1.html#payload-replacement-object)
  """
  alias Cuerdo.Arazzo.{Context, RuntimeExpression, Selector}

  alias Cuerdo.Traversal

  @type t :: %__MODULE__{}

  use Cuerdo.Object,
    schema: %{
      target: Zoi.string(),
      value: Zoi.union([Selector.schema(), Zoi.any()]),
      targetSelectorType:
        Zoi.string() |> Zoi.one_of(["jsonpath", "jsonpointer"]) |> Zoi.default("jsonpointer")
    }

  @doc """
  Applies a single replacement to a payload body.

  A single replacement expression might affect multiple paths if "jsonpath" is provided.
  For example with `target: "$[? @.price < 100]"` a replacement is applied to all elements
  where `price < 100`.
  """
  @spec apply(t(), any(), Traversal.execution_path(), Context.t()) ::
          {:ok, any()} | {:error, Exception.t()}
  def apply(%__MODULE__{} = replacement, body, rev_path, %Context{} = ctx) do
    with {:ok, paths} <- targets(replacement, body),
         {:ok, new_value} <- RuntimeExpression.resolve(replacement.value, rev_path, ctx) do
      Enum.reduce_while(paths, {:ok, body}, fn path, {:ok, body} ->
        case RockSolid.Traversal.put_in_schema(body, path, new_value) do
          {:ok, updated_body} -> {:cont, {:ok, updated_body}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  @doc """
  Same as `apply/4` but applies a list of replacements.
  """
  @spec apply(list(t), any(), Traversal.execution_path(), Context.t()) ::
          {:ok, any()} | {:error, Exception.t()}
  def apply_many(replacements, expanded_body, rev_path, ctx) when is_list(replacements) do
    Enum.reduce_while(
      replacements,
      {:ok, expanded_body},
      fn %__MODULE__{} = replacement, {:ok, body} ->
        case apply(replacement, body, rev_path, ctx) do
          {:ok, body} -> {:cont, {:ok, body}}
          {:error, _} = error -> {:halt, error}
        end
      end
    )
  end

  defp targets(%__MODULE__{targetSelectorType: "jsonpointer", target: target}, _) do
    {:ok, [RockSolid.Traversal.to_path(target)]}
  end

  defp targets(%__MODULE__{targetSelectorType: "jsonpath", target: target}, body) do
    case JSONPath.paths(body, target) do
      {:ok, path} -> {:ok, Enum.map(path, &to_path/1)}
      {:error, e} = error when is_exception(e) -> error
    end
  end

  # Custom function because we receive normalized paths, not JSON pointers, we can't use
  # RockSolid.Traversal.to_path/1
  def to_path("$" <> traversal), do: to_path(to_codepoints(traversal), [])
  defp to_path([], acc), do: Enum.reverse(acc)

  defp to_path([?[, ?' | string_prop], acc) do
    {prop, rest} = collect_string(string_prop)
    to_path(rest, [prop | acc])
  end

  # Must be an index
  defp to_path([?[ | rest], acc) do
    {index, [?] | rest]} = Enum.split_while(rest, &(&1 in ?0..?9))
    index = index |> to_string()

    to_path(rest, [index | acc])
  end

  defp collect_string(string), do: collect_string(string, [])
  defp collect_string([?', ?] | rest], acc), do: {Enum.reverse(acc) |> to_string(), rest}
  # De-escape single quotes and other escaped chars
  defp collect_string([?\\, ?' | rest], acc), do: collect_string(rest, [?' | acc])
  defp collect_string([?\\, ?t | rest], acc), do: collect_string(rest, [?\t | acc])
  defp collect_string([?\\, ?r | rest], acc), do: collect_string(rest, [?\r | acc])
  defp collect_string([?\\, ?n | rest], acc), do: collect_string(rest, [?\n | acc])
  defp collect_string([?\\, ?b | rest], acc), do: collect_string(rest, [?\b | acc])
  defp collect_string([?\\, ?f | rest], acc), do: collect_string(rest, [?\f | acc])
  defp collect_string([?\\, ?\\ | rest], acc), do: collect_string(rest, [?\\ | acc])
  defp collect_string([char | rest], acc), do: collect_string(rest, [char | acc])

  defp to_codepoints(str) when is_binary(str) do
    for <<c::utf8 <- str>>, do: c
  end
end
