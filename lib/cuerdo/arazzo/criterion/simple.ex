defmodule Cuerdo.Arazzo.Criterion.Simple do
  @moduledoc """
  "simple" Criterion expressions evaluator
  """

  defguardp is_whitespace(s) when s in [?\s, ?\r, ?\n, ?\t, ?\f, ?\v]
  defguardp can_be_number(val) when is_number(val) or is_binary(val)

  alias Cuerdo.Arazzo.{Context, RuntimeExpression}
  alias Cuerdo.Errors.InvalidExpression

  @number_codepoints [?e, ?E, ?., ?-, ?+] ++ Enum.to_list(?0..?9)
  @comparison_operators [:gt, :gte, :eq, :neq, :lt, :lte]

  @doc """
  Evaluates a condition. Returns `{:ok, boolean()}` if the condition was evaluated, or
  an error tuple if there was any error evaluating the condition
  """
  @spec evaluate(String.t(), list(), Context.t()) :: {:ok, boolean()} | {:error, any()}
  def evaluate(condition, rev_path, %Context{} = context) when is_binary(condition) do
    case parse(condition) do
      {:ok, ast} ->
        {:ok, do_evaluate(ast, rev_path, context)}

      {:error, e} when is_binary(e) ->
        {:error, %InvalidExpression{expression: condition, message: e}}
    end
  catch
    {:error, exc} when is_exception(exc) ->
      {:error, %InvalidExpression{expression: condition, message: Exception.message(exc)}}

    {:error, msg} when is_binary(msg) ->
      {:error, %InvalidExpression{expression: condition, message: msg}}
  end

  # Values
  defp do_evaluate({:literal, value}, _rev_path, _ctx), do: value

  defp do_evaluate({:runtime_expression, expression}, rev_path, context) do
    case RuntimeExpression.resolve(expression, rev_path, context) do
      {:ok, value} -> value
      {:error, exc} = error when is_exception(exc) -> throw(error)
    end
  end

  # Booleans
  # Elixir `not`, `or`, `and` expect always boolean as operands. We could use !, ||, &&
  # but it's better to fail here because expression should always evaluate to booleans
  defp do_evaluate({:not, expr}, rev_path, ctx), do: not do_evaluate(expr, rev_path, ctx)

  defp do_evaluate({:or, left, right}, rev_path, ctx) do
    do_evaluate(left, rev_path, ctx) or do_evaluate(right, rev_path, ctx)
  end

  defp do_evaluate({:and, left, right}, rev_path, ctx) do
    do_evaluate(left, rev_path, ctx) and do_evaluate(right, rev_path, ctx)
  end

  # Comparisons
  defp do_evaluate({op, left, right}, rev_path, ctx) do
    left_val = do_evaluate(left, rev_path, ctx) |> case_insensitive()
    right_val = do_evaluate(right, rev_path, ctx) |> case_insensitive()

    case op do
      :eq -> left_val == right_val
      :neq -> left_val != right_val
      :gt -> number_cmp(left_val, right_val, &Kernel.>/2)
      :lt -> number_cmp(left_val, right_val, &Kernel.</2)
      :gte -> left_val == right_val or number_cmp(left_val, right_val, &Kernel.>/2)
      :lte -> left_val == right_val or number_cmp(left_val, right_val, &Kernel.</2)
    end
  end

  defp case_insensitive(str) when is_binary(str), do: String.downcase(str)
  defp case_insensitive(not_a_string), do: not_a_string

  defp number_cmp(left, right, func) when can_be_number(left) and can_be_number(right) do
    with {:ok, left_num} <- to_number(left),
         {:ok, right_num} <- to_number(right) do
      func.(left_num, right_num)
    else
      _ -> false
    end
  end

  defp number_cmp(_, _, _), do: false

  defp to_number(val) when is_number(val), do: {:ok, val}

  defp to_number(val) when is_binary(val) do
    case Integer.parse(val) do
      {int_val, ""} ->
        {:ok, int_val}

      _ ->
        case Float.parse(val) do
          {float_val, ""} -> {:ok, float_val}
          _ -> {:error, "not a number: #{val}"}
        end
    end
  end

  @doc """
  Parses a condition into an AST that can later be evaluated
  """
  def parse(condition) when is_binary(condition) do
    with {:ok, tokens} <- tokenize(condition),
         {ast, []} <- parse_or(tokens) do
      {:ok, ast}
    end
  catch
    {:error, _} = error -> error
  end

  def tokenize(condition) when is_binary(condition), do: tokenize(to_codepoints(condition), [])

  defp tokenize([], acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize([s | rest], acc) when is_whitespace(s), do: tokenize(rest, acc)

  defp tokenize([?$ | _] = tokens, acc) do
    {runtime_expression, rest} = Enum.split_while(tokens, &(&1 != ?\s))
    tokenize(rest, [{:runtime_expression, to_string(runtime_expression)} | acc])
  end

  defp tokenize([?t, ?r, ?u, ?e | rest], acc), do: tokenize(rest, [{:literal, true} | acc])
  defp tokenize([?f, ?a, ?l, ?s, ?e | rest], acc), do: tokenize(rest, [{:literal, false} | acc])
  defp tokenize([?n, ?u, ?l, ?l | rest], acc), do: tokenize(rest, [{:literal, nil} | acc])
  defp tokenize([?&, ?& | rest], acc), do: tokenize(rest, [:and | acc])
  defp tokenize([?|, ?| | rest], acc), do: tokenize(rest, [:or | acc])
  defp tokenize([?=, ?= | rest], acc), do: tokenize(rest, [:eq | acc])
  defp tokenize([?>, ?= | rest], acc), do: tokenize(rest, [:gte | acc])
  defp tokenize([?<, ?= | rest], acc), do: tokenize(rest, [:lte | acc])
  defp tokenize([?!, ?= | rest], acc), do: tokenize(rest, [:neq | acc])
  defp tokenize([?> | rest], acc), do: tokenize(rest, [:gt | acc])
  defp tokenize([?< | rest], acc), do: tokenize(rest, [:lt | acc])
  defp tokenize([?! | rest], acc), do: tokenize(rest, [:not | acc])
  defp tokenize([?( | rest], acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize([?) | rest], acc), do: tokenize(rest, [:rparen | acc])

  defp tokenize([?' | rest], acc) do
    case collect_string(rest) do
      {:ok, {str, rest}} -> tokenize(rest, [{:literal, str} | acc])
      {:error, _} = error -> error
    end
  end

  defp tokenize([c | _] = tokens, acc) when c in @number_codepoints do
    {number, rest} = Enum.split_while(tokens, &(&1 in @number_codepoints))
    number_str = to_string(number)

    case to_number(number_str) do
      {:ok, number} -> tokenize(rest, [{:literal, number} | acc])
      _ -> throw({:error, "invalid number: #{number_str}"})
    end
  end

  defp tokenize([char | _], _), do: throw({:error, "unknown character: #{<<char>>}"})

  defp collect_string(tokens), do: collect_string(tokens, [])
  defp collect_string([?\\, ?' | rest], acc), do: collect_string(rest, [?' | acc])
  defp collect_string([?' | rest], acc), do: {:ok, {Enum.reverse(acc) |> to_string(), rest}}
  defp collect_string([char | rest], acc), do: collect_string(rest, [char | acc])

  defp collect_string([], acc),
    do: throw({:error, "unterminated single-quoted string: #{Enum.reverse(acc) |> to_string()}"})

  defp to_codepoints(str) when is_binary(str) do
    for <<c::utf8 <- str>>, do: c
  end

  # Parsing, same algorithm used in JSONPath package
  defp parse_or(tokens) do
    {left, tokens} = parse_and(tokens)
    parse_or_rest(left, tokens)
  end

  defp parse_or_rest(left, [:or | rest]) do
    {right, rest} = parse_and(rest)
    parse_or_rest({:or, left, right}, rest)
  end

  defp parse_or_rest(left, tokens), do: {left, tokens}

  defp parse_and(tokens) do
    {left, tokens} = parse_cmp(tokens)
    parse_and_rest(left, tokens)
  end

  defp parse_and_rest(left, [:and | rest]) do
    {right, rest} = parse_cmp(rest)
    parse_and_rest({:and, left, right}, rest)
  end

  defp parse_and_rest(left, tokens), do: {left, tokens}

  defp parse_cmp(tokens) do
    {left, tokens} = parse_not(tokens)
    parse_cmp_rest(left, tokens)
  end

  defp parse_cmp_rest(left, [op | rest]) when op in @comparison_operators do
    {right, rest} = parse_not(rest)
    parse_cmp_rest({op, left, right}, rest)
  end

  defp parse_cmp_rest(left, tokens), do: {left, tokens}

  defp parse_not([:not | rest]) do
    {expr, rest} = parse_not(rest)
    {{:not, expr}, rest}
  end

  defp parse_not(tokens), do: parse_primary(tokens)

  defp parse_primary([{:runtime_expression, _} = runtime_expr | rest]), do: {runtime_expr, rest}
  defp parse_primary([{:literal, _} = lit | rest]), do: {lit, rest}

  defp parse_primary([:lparen | rest]) do
    case parse_or(rest) do
      {expr, [:rparen | rest]} -> {expr, rest}
      _ -> throw({:error, "missing closing ')'"})
    end
  end

  defp parse_primary([token | _]), do: throw({:error, "unexpected token: #{inspect(token)}"})
  defp parse_primary([]), do: throw({:error, "unexpected end of input"})
end
