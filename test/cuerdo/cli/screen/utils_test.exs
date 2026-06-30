defmodule Cuerdo.CLI.Screen.UtilsTest do
  use ExUnit.Case

  alias Cuerdo.ArazzoCase.Result
  alias Cuerdo.CLI.Screen

  describe "summary/1" do
    test "returns execution time in seconds when total exceeds 1s" do
      results = [%Result{status: :passed, execution_time_ms: 1_200}]

      expected = "1 passed · 0 failed · 1 total · 1.2s"
      assert expected == Screen.Utils.summary(results)
    end

    test "counts failed passed for total" do
      results = [
        %Result{status: :passed, execution_time_ms: 1_200},
        %Result{status: :failed, execution_time_ms: 300}
      ]

      expected = "1 passed · 1 failed · 2 total · 1.5s"
      assert expected == Screen.Utils.summary(results)
    end
  end
end
