defmodule Cuerdo.Arazzo.ReplacementTest do
  use ExUnit.Case

  import Cuerdo.ArazzoFixtures
  alias Cuerdo.Arazzo.{Context, Replacement}
  alias Cuerdo.Errors.InvalidSelector

  describe "to_pointer/1" do
    test "parses indexes and strings" do
      assert ["foo", "0", "bar"] == Replacement.to_path("$['foo'][0]['bar']")
    end

    test "de-escapes escaped characters" do
      normalized_path = "$['\\\\']['\\b']['\\n']['\\t']['\\r']['\\f']"
      assert ["\\", "\b", "\n", "\t", "\r", "\f"] == Replacement.to_path(normalized_path)
    end
  end

  describe "apply/3" do
    test "JSONPath target with constant selector applies multiple replacements" do
      context =
        people_document()
        |> Context.new!()
        |> Context.put_inputs("getPeople", %{"name" => "John"})

      body = [
        %{"name" => "Alice", "age" => 20},
        %{"name" => "Bob", "age" => 30},
        %{"name" => "Charlie", "age" => 25}
      ]

      replacement = %{
        "target" => "$[?@.age < 30].name",
        "value" => "$inputs.name",
        "targetSelectorType" => "jsonpath"
      }

      rev_path = [0, "steps", 0, "workflows"]

      assert {:ok, [%{"name" => "John"}, %{"name" => "Bob"}, %{"name" => "John"}]} =
               replacement
               |> Replacement.new!()
               |> Replacement.apply(body, rev_path, context)
    end

    test "replacement with JSONPointer selector" do
      inputs = %{"nested" => [%{"input" => %{"name" => "David"}}]}

      context =
        people_document()
        |> RockSolid.Traversal.put_in_schema!(["workflows", "0", "inputs"], %{
          "type" => "object",
          "properties" => %{"nested" => %{"type" => "object"}}
        })
        |> Context.new!()
        |> Context.put_inputs("getPeople", inputs)

      body = %{}
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{
        "target" => "#/name",
        "value" => %{
          "context" => "$inputs.nested",
          "type" => "jsonpointer",
          "selector" => "/0/input/name"
        }
      }

      assert {:ok, %{"name" => "David"}} =
               replacement
               |> Replacement.new!()
               |> Replacement.apply(body, rev_path, context)
    end

    test "constant value with JSONPath selector containing single quote in property" do
      context = Context.new!(people_document())
      body = [%{"O'Connor" => "Sarah"}]
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{
        "target" => "$[?@[\"O'Connor\"] == \"Sarah\"][\"O'Connor\"]",
        "value" => "John",
        "targetSelectorType" => "jsonpath"
      }

      assert {:ok, [%{"O'Connor" => "John"}]} ==
               replacement |> Replacement.new!() |> Replacement.apply(body, rev_path, context)
    end

    test "JSONPath selector capturing multiple values returns error" do
      inputs = [
        %{"age" => 20, "name" => "Alice"},
        %{"age" => 30, "name" => "Bob"}
      ]

      context =
        people_document()
        |> RockSolid.Traversal.put_in_schema!(["workflows", "0", "inputs"], %{
          "type" => "object",
          "properties" => %{"people" => %{"type" => "array"}}
        })
        |> Context.new!()
        |> Context.put_inputs("getPeople", %{"people" => inputs})

      body = %{"name" => "Another one"}
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{
        "target" => "#/name",
        "value" => %{
          "context" => "$inputs.people",
          "type" => "jsonpath",
          "selector" => "$[?@.age >= 20].name"
        }
      }

      assert {:error, %InvalidSelector{}} =
               replacement
               |> Replacement.new!()
               |> Replacement.apply(body, rev_path, context)
    end

    test "invalid JSON Pointer target with constant selector returns error" do
      context = Context.new!(people_document())

      body = %{"name" => "name"}
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{"target" => "#/foo/bar", "value" => "baz"}

      assert {:error, _} =
               replacement
               |> Replacement.new!()
               |> Replacement.apply(body, rev_path, context)
    end

    test "JSON Pointer target with JSONPath selector applies single value" do
      inputs = [
        %{"age" => 20, "name" => "Alice"},
        %{"age" => 30, "name" => "Bob"}
      ]

      context =
        people_document()
        |> RockSolid.Traversal.put_in_schema!(["workflows", "0", "inputs"], %{
          "type" => "object",
          "properties" => %{"people" => %{"type" => "array"}}
        })
        |> Context.new!()
        |> Context.put_inputs("getPeople", %{"people" => inputs})

      body = %{"name" => "Another one"}
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{
        "target" => "#/name",
        "value" => %{
          "context" => "$inputs.people",
          "type" => "jsonpath",
          "selector" => "$[?@.age == 20].name"
        }
      }

      assert {:ok, %{"name" => "Alice"}} =
               replacement
               |> Replacement.new!()
               |> Replacement.apply(body, rev_path, context)
    end
  end

  describe "apply_many/3" do
    test "returns error when JSONPath target is invalid" do
      context = Context.new!(people_document())
      body = %{}
      rev_path = [0, "steps", 0, "workflows"]

      replacement = %{
        "target" => "$[@ > 1]",
        "value" => "John",
        "targetSelectorType" => "jsonpath"
      }

      assert {:error, %JSONPath.Error{}} =
               Replacement.apply_many([Replacement.new!(replacement)], body, rev_path, context)
    end
  end
end
