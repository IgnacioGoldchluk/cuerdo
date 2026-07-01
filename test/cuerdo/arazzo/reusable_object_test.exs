defmodule Cuerdo.Arazzo.ReusableObjectTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.ReusableObject

  import Cuerdo.ArazzoFixtures

  describe "resolve/2" do
    test "returns error when parameter does not exist" do
      reusable_object = ReusableObject.new!(%{"reference" => "$components.parameters.invalid"})

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                type: :parameter,
                expression: "$components.parameters.invalid",
                value: "not in document"
              }} ==
               ReusableObject.resolve(reusable_object, default_context())
    end
  end
end
