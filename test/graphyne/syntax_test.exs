defmodule Graphyne.SyntaxTest do
  use ExUnit.Case, async: true

  alias Graphyne.Syntax

  describe "check/1 accepts" do
    test "a named operation with variables, aliases, directives and literals" do
      text = """
      # A comment, commas and every kind of value
      query Full($id: ID!, $ids: [ID!]! = ["1"], $skip: Boolean = false) {
        item: property(id: $id, source: PRIMARY) @skip(if: $skip) {
          list(ids: $ids, input: {a: 1, b: -2.5e3, c: "x\\"y", d: \"\"\"block\"\"\", e: null, f: [true, ON]})
          query mutation fragment on true
          ... on Property { id }
          ... @include(if: true) { id }
        }
      }
      """

      assert {:ok, %{name: "Full", variables: ["id", "ids", "skip"], missing_fragments: []}} = Syntax.check(text)
    end

    test "a mutation that uses a fragment" do
      text = """
      mutation Save($input: SaveInput!) { save(input: $input) { ...Saved } }
      fragment Saved on SavePayload { id status }
      """

      assert {:ok, %{name: "Save", variables: ["input"], missing_fragments: []}} = Syntax.check(text)
    end

    test "a variable that only a nested fragment uses" do
      text = """
      query Q($v: Int) { a { ...F } }
      fragment F on A { ...G }
      fragment G on A { b(x: $v) }
      """

      assert {:ok, %{name: "Q", variables: ["v"], missing_fragments: []}} = Syntax.check(text)
    end

    test "a spread of a fragment from another document, and returns its name" do
      assert {:ok, %{name: "Q", variables: ["id"], missing_fragments: ["F", "G"]}} =
               Syntax.check("query Q($id: ID) { ...G a { ...F } ...F }")
    end

    test "a document with fragments only" do
      assert {:ok, %{name: nil, variables: [], missing_fragments: []}} =
               Syntax.check("fragment F on A { b(x: $v) ...G }")
    end
  end

  describe "check/1 rejects" do
    test "a syntax error, with its line" do
      assert {:error, 2, message} = Syntax.check("query Q {\n  a(b: ) }")
      assert message =~ "syntax error before"
    end

    test "an unknown character" do
      assert {:error, 1, message} = Syntax.check("query Q { a | b }")
      assert message =~ "illegal characters"
    end

    test "an unclosed selection set at the end of the text" do
      assert {:error, 3, _message} = Syntax.check("query Q {\n  a {\n    b }")
    end

    test "an operation without a name" do
      assert {:error, 1, "the operation has no name"} = Syntax.check("{ a }")
    end

    test "two operations" do
      assert {:error, 2, "the document has more than one operation"} = Syntax.check("query A { a }\nquery B { b }")
    end

    test "an undeclared variable" do
      assert {:error, 2, "the variable $id has no declaration"} = Syntax.check("query Q {\n  a(id: $id) }")
    end

    test "an unused variable" do
      assert {:error, 1, "the operation does not use the variable $id"} = Syntax.check("query Q($id: ID) { a }")
    end

    test "a variable that has two definitions" do
      assert {:error, 1, "the variable $id has more than one definition"} =
               Syntax.check("query Q($id: ID, $id: ID) { a(id: $id) }")
    end

    test "a default that uses a variable" do
      assert {:error, 1, "the default of $b uses a variable"} =
               Syntax.check("query Q($a: Int, $b: Int = $a) { f(a: $a, b: $b) }")
    end

    test "an unused fragment" do
      assert {:error, 2, "the operation does not use the fragment F"} =
               Syntax.check("query Q { a }\nfragment F on A { b }")
    end

    test "a fragment that has two definitions" do
      assert {:error, 3, "the fragment F has more than one definition"} =
               Syntax.check("query Q { ...F }\nfragment F on A { a }\nfragment F on A { b }")
    end
  end
end
