defmodule Cuerdo.Arazzo.RuntimeExpression do
  @moduledoc """
  Wrapper for a runtime expression or selector
  """
  alias Cuerdo.Arazzo.{Context, Selector}
  alias Cuerdo.Errors.InvalidExpression
  alias Cuerdo.Traversal

  @schema Zoi.union([Selector.schema(), Zoi.string()])
  def schema, do: @schema

  @doc """
  Replaces all runtime expressions in the given JSON object. Returns a tuple `{:ok, updated}`
  with `updated` being the input payload with all replacements applied, or `{:error, Excepton.t()}`
  if any expresion fails to evaluate
  """
  @spec resolve(Selector.t() | any(), Traversal.execution_path(), Context.t()) ::
          {:ok, any()} | {:error, Exception.t()}
  def resolve(payload, reversed_path, context) do
    {:ok, do_resolve(payload, reversed_path, context)}
  catch
    {:error, e} = error when is_exception(e) -> error
  end

  # Special case for values inside payloads
  defp do_resolve(
         %{"context" => context, "type" => type, "selector" => selector} = payload,
         rev_path,
         %Context{} = ctx
       )
       when is_binary(context) and type in ["jsonpath", "jsonpointer"] and is_binary(selector) do
    path = Enum.reverse(rev_path)

    with {:unambiguous?, true} <-
           {:unambiguous?,
            match?(["workflows", _, "steps", _, "requestBody", "payload" | _], path)},
         {:ok, replaced} <- resolve(context, rev_path, ctx),
         {:ok, selector_resolved} <- Selector.resolve(replaced, type, selector) do
      selector_resolved
    else
      {:unambiguous?, false} ->
        message = "ambiguous payload #{inspect(payload)} could be literal or selector"
        throw({:error, %InvalidExpression{expression: payload, message: message}})

      {:error, e} = error when is_exception(e) ->
        throw(error)
    end
  end

  defp do_resolve(
         %Selector{context: context, type: type, selector: selector},
         reversed_path,
         %Context{} = ctx
       ) do
    with {:ok, value} <- resolve(context, reversed_path, ctx),
         {:ok, selector_resolved} <- Selector.resolve(value, type, selector) do
      selector_resolved
    else
      {:error, e} = error when is_exception(e) -> throw(error)
    end
  end

  defp do_resolve(document, reversed_path, ctx) when is_map(document) do
    Map.new(document, fn {key, value} ->
      {key, do_resolve(value, [key | reversed_path], ctx)}
    end)
  end

  defp do_resolve(document, reversed_path, ctx) when is_list(document) do
    document
    |> Enum.with_index()
    |> Enum.map(fn {element, index} ->
      do_resolve(element, [index | reversed_path], ctx)
    end)
  end

  defp do_resolve(val, _rev_path, _ctx) when is_nil(val) or is_boolean(val) or is_number(val) do
    val
  end

  defp do_resolve(value, reversed_path, ctx) when is_binary(value) do
    pattern = ~r/\{?(\$[\w-][\w.-]*)(#[^}]+)?\}?/

    # Cases
    # 1. When the entire string matches, for example `$inputs.foo` we have to directly
    # replace instead of doing string interpolation. This includes JSON pointer too, except
    # when the JSON pointer is part of `$sourceDescription`, in that case we replace the
    # sourceDescription (first part) but keep the JSON pointer.
    case Regex.scan(pattern, value) do
      [] ->
        value

      [[full_string, full_string]] when full_string == value ->
        # No need to apply anything since the full string matched
        Traversal.fetch_value(full_string, reversed_path, ctx) |> or_throw()

      [[full_string, json_path, pointer]] when full_string == json_path <> pointer ->
        if String.starts_with?(json_path, "$sourceDescription") do
          # For `$sourceDescription, since everything is internal we keep the JSON pointer
          json_path
          |> Traversal.fetch_value(reversed_path, ctx)
          |> or_throw()
          |> then(&(&1 <> pointer))
        else
          Traversal.fetch_value({json_path, pointer}, reversed_path, ctx) |> or_throw()
        end

      _multiple_matches ->
        # Here we have to convert everything to string interpolation
        Regex.replace(pattern, value, fn
          _full, "$sourceDescription" <> _ = json_path, json_pointer ->
            json_path
            |> Traversal.fetch_value(reversed_path, ctx)
            |> or_throw()
            |> to_string()
            |> then(&(&1 <> json_pointer))

          _full, json_path, "" ->
            Traversal.fetch_value(json_path, reversed_path, ctx) |> or_throw() |> to_string()

          _full, json_path, json_pointer ->
            Traversal.fetch_value({json_path, json_pointer}, reversed_path, ctx)
            |> or_throw()
            |> to_string()
        end)
    end
  end

  defp or_throw({:ok, value}), do: value
  defp or_throw({:error, _} = error), do: throw(error)
end
