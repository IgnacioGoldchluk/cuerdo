defmodule Cuerdo.ArazzoCase.OptsTest do
  use Cuerdo.ArazzoCase

  import Cuerdo.ArazzoFixtures

  def prefix_name(filters) do
    StreamData.constant(Map.update!(filters, "name", &("PERSON_" <> &1)))
  end

  describe "custom input step" do
    setup do
      Req.Test.expect(Cuerdo.Client, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        assert String.starts_with?(name, "PERSON_")

        Req.Test.json(conn, [
          %{"name" => "#{name}abc", "age" => min_age + 2},
          %{"name" => "#{name}bcd", "age" => min_age + 20}
        ])
      end)

      :ok
    end

    arazzo_document_test max_runs: 1,
                         document: people_document(with_self: true),
                         transform_inputs: %{"getPeople" => {__MODULE__, :prefix_name, []}}
  end

  describe "prefix allows same document to be tested" do
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

    arazzo_document_test max_runs: 1, document: people_document(with_self: true)
    arazzo_document_test max_runs: 1, prefix: "again", document: people_document(with_self: true)
  end
end
