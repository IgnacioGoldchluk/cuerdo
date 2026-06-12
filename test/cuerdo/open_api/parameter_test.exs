defmodule Cuerdo.OpenAPI.ParameterTest do
  use ExUnit.Case

  alias Cuerdo.OpenAPI.Parameter

  describe "new/1" do
    test "returns error when parameter in path is not required" do
      parameter = %{"name" => "id", "in" => "path", "required" => false}

      assert {:error, [%Zoi.Error{message: msg}]} = Parameter.new(parameter)
      assert msg == "parameter in path must have required = true"
    end
  end
end
