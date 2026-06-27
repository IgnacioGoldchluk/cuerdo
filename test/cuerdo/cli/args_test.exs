defmodule Cuerdo.CLI.ArgsTest do
  use ExUnit.Case

  alias Cuerdo.CLI

  describe "parse/1" do
    test "--exclude and --only accept comma-separated workflow ids" do
      opts = ["--only", "id1,id3", "--exclude", "id4"]

      assert {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:only] == ["id1", "id3"]
      assert parsed[:exclude] == ["id4"]
    end

    test "--report-file passes" do
      opts = ["--report-file", "log"]

      assert {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:report_file] == "log"
    end

    test "parses num-runs as integer" do
      opts = ["--num-runs", "123"]

      {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:num_runs] == 123
      assert parsed[:halt_on_error] == false
    end

    test "halt-on-error is set to true when present" do
      opts = ["--halt-on-error"]

      {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:halt_on_error] == true
    end

    test "returns error when receiving unknown args" do
      opts = ["--unknown-flag", "yes"]
      assert {:error, %CLI.Errors.UnexpectedArgs{} = error} = CLI.Args.parse(opts)
      assert "Unexpected arguments: --unknown-flag" == Exception.message(error)
    end
  end
end
