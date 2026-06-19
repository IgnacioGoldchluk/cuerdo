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

    test "--report-file with stdout output passes" do
      opts = ["--report-output", "stdout", "--report-file", "log"]

      assert {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:report_output] == :stdout
    end

    test "missing --report-file returns error" do
      opts = ["--report-output", "json"]
      assert {:error, %ArgumentError{message: "--report-output=json" <> _}} = CLI.Args.parse(opts)
    end

    test "--report-output invalid returns an error" do
      opts = ["--report-output", "xml", "--report-file", "file.xml"]

      assert {:error, %NimbleOptions.ValidationError{key: :report_output, value: "xml"}} =
               CLI.Args.parse(opts)
    end

    test "--report-output is converted to atom" do
      opts = ["--report-output", "json", "--report-file", "file.json"]

      {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:report_output] == :json

      opts = ["--report-output", "stdout"]
      {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:report_output] == :stdout

      # Default case
      opts = []
      {:ok, parsed} = CLI.Args.parse(opts)
      assert parsed[:report_output] == :stdout
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
