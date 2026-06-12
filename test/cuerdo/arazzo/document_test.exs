defmodule Cuerdo.Arazzo.DocumentTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Document

  describe "resolve_self" do
    test "absolute URL in '$self' is left as is" do
      document = %{"$self" => "https://api.example.com/workflows/arazzo.yaml"}

      assert document == Document.resolve_self(document, "file:///home/workflows/arazzo.yaml")

      assert document ==
               Document.resolve_self(document, "https://api2.example2.com/workflows/arazzo.yaml")
    end

    test "relative URL in '$self' is merged with base URI used to fetch the document" do
      document = %{"$self" => "workflows/arazzo.yaml"}

      assert "https://api.example.com/workflows/arazzo.yaml" ==
               Document.resolve_self(
                 document,
                 "https://api.example.com"
               )["$self"]

      assert "https://api.example.com/workflows/arazzo.yaml" ==
               Document.resolve_self(
                 document,
                 "https://api.example.com/otherdocument.yaml"
               )["$self"]

      assert "file:///home/workflows/arazzo.yaml" ==
               Document.resolve_self(
                 document,
                 "file:///home/arazzo2.yaml"
               )["$self"]
    end
  end

  describe "new/1" do
    test "sets $self to current path by default" do
      {:ok, document} =
        ["test", "support", "arazzo.yaml"]
        |> Path.join()
        |> YamlElixir.read_from_file!()
        |> Document.new()

      assert Map.fetch!(document, :"$self") == "file://#{File.cwd!()}/"
    end

    test "returns error if '$self' URI contains fragment" do
      document =
        ["test", "support", "arazzo.yaml"]
        |> Path.join()
        |> YamlElixir.read_from_file!()
        |> Map.put("$self", "https://example.com/arazzo.yaml#fragmentpath")

      assert {:error, [%Zoi.Error{message: msg}]} = Document.new(document)
      assert msg == "cannot contain fragment"
    end

    test "loads valid Arazzo file" do
      {:ok, contents} =
        Path.join(["test", "support", "arazzo.yaml"])
        |> YamlElixir.read_from_file()

      assert {:ok, %Document{} = document} = Document.new(contents)
      assert length(document.workflows) == length(contents["workflows"])
      assert document.arazzo == contents["arazzo"]
    end

    test "returns error for empty workflows" do
      contents =
        Path.join(["test", "support", "arazzo.yaml"])
        |> YamlElixir.read_from_file!()
        |> Map.delete("workflows")

      assert {:error, [%Zoi.Error{path: [:workflows], message: msg}]} = Document.new(contents)
      assert msg == "is required"
    end
  end
end
