defmodule Cuerdo.CLI.ScreenTest do
  use ExUnit.Case

  alias Cuerdo.CLI.Screen

  describe "mode/1" do
    test "returns screen module for mode" do
      assert Screen.mode("none") == Screen.Dummy
      assert Screen.mode("rich") == Screen.Terminal
      assert Screen.mode("basic") == Screen.Basic
    end
  end
end
