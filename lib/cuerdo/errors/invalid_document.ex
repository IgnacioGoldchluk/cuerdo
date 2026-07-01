defmodule Cuerdo.Errors.InvalidDocument do
  defexception [:errors]

  def message(%{errors: errors}) do
    """
    Arazzo Document is invalid:

    #{stringify(errors |> Zoi.treefy_errors())}
    """
  end

  defp stringify(errors, rev_path \\ []) do
    Enum.map_join(errors, "\n", fn {key, values} ->
      cond do
        is_list(values) ->
          path = Enum.reverse([key | rev_path]) |> Enum.map_join(".", &to_string/1)
          "#{path}: #{Enum.join(values, ", ")}"

        is_map(values) ->
          stringify(values, [key | rev_path])
      end
    end)
  end
end
