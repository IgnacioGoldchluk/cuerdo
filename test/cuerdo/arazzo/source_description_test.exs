defmodule Cuerdo.Arazzo.SourceDescriptionTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.SourceDescription

  describe "new/1" do
    test "creates source description with nil (unfetched) value" do
      source_description = %{
        "type" => "arazzo",
        "url" => "https://example.com/arazzo.yaml",
        "name" => "exampleSourceDescription"
      }

      assert {:ok, %SourceDescription{value: nil}} = SourceDescription.new(source_description)
    end
  end
end
