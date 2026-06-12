defmodule Cuerdo.ArazzoCaseTest do
  use Cuerdo.ArazzoCase

  setup do
    Req.Test.expect(Cuerdo.Client, fn conn ->
      %{"min_age" => min_age, "name" => name} = conn.params
      min_age = String.to_integer(min_age)

      Req.Test.json(conn, [
        %{"name" => "#{name}abc", "age" => min_age + 2},
        %{"name" => "#{name}bcd", "age" => min_age + 20}
      ])
    end)

    :ok
  end

  arazzo_document_test max_runs: 1,
                       document:
                         Path.join(["test", "support", "people", "arazzo.yaml"])
                         |> YamlElixir.read_from_file!()
                         |> Map.put(
                           "$self",
                           Path.join(["test", "support", "people", "arazzo.yaml"])
                         )
end
