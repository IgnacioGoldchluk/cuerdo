defmodule Cuerdo.GraphTest do
  use ExUnit.Case

  alias Cuerdo.Graph

  doctest Graph

  describe "cyclic?/1" do
    test "returns true for cyclic dependsOn" do
      depends_on = %{a: [:b, :c], b: [:c, :d], c: [:e, :d], e: [:f], f: [:a]}
      assert Graph.cyclic?(depends_on)
    end
  end
end
