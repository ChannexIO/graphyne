defmodule GraphyneTest do
  use ExUnit.Case, async: true
  use Graphyne

  alias Graphyne.Error

  @query ~GQL"""
  query Find($id: ID!, $after: String) {
    item(id: $id, after: $after) { ...Item }
  }
  """

  @fragment ~GQL"fragment Item on Item { id }"

  @composed compose(@query, [@fragment])

  describe "~GQL" do
    test "keeps the operation name, the text and the missing fragments" do
      assert %Graphyne{name: "Find", variables: ["after", "id"], missing_fragments: ["Item"]} = @query
      assert %Graphyne{name: nil, text: "fragment Item on Item { id }", missing_fragments: []} = @fragment
    end

    test "fails the compile with the line of the error in the caller file" do
      code = """
      defmodule GraphyneTest.Broken do
        use Graphyne

        @query ~GQL\"\"\"
        query Broken {
          item(id: $id) { id }
        }
        \"\"\"
      end
      """

      error = assert_raise CompileError, fn -> Code.compile_string(code, "broken.ex") end
      assert Exception.message(error) =~ "broken.ex:6: ~GQL: the variable $id has no declaration"
    end

    test "counts lines from the sigil line for a one-line document" do
      code = """
      defmodule GraphyneTest.BrokenLine do
        use Graphyne

        @query ~GQL"query Broken { item(id: ) }"
      end
      """

      error = assert_raise CompileError, fn -> Code.compile_string(code, "broken_line.ex") end
      assert Exception.message(error) =~ "broken_line.ex:4: ~GQL: syntax error before"
    end
  end

  describe "compose/2" do
    test "works in a module attribute at compile time" do
      assert %Graphyne{name: "Find", missing_fragments: []} = @composed
    end

    test "appends fragments and checks the result" do
      assert %Graphyne{name: "Find", missing_fragments: [], text: text} = compose(@query, [@fragment])
      assert text =~ "fragment Item on Item"
    end

    test "raises when a fragment is still missing" do
      assert_raise ArgumentError, ~r/Find has no definition of the fragments Item/, fn -> compose(@query, []) end
    end

    test "raises on a fragment that the document does not use" do
      unused = ~GQL"fragment Unused on Item { id }"

      assert_raise ArgumentError, ~r/the operation does not use the fragment Unused/, fn ->
        compose(@query, [@fragment, unused])
      end
    end
  end

  describe "payload/2" do
    test "sends the operation name and leaves out nil variables" do
      document = compose(@query, [@fragment])

      assert %{"query" => text, "operationName" => "Find", "variables" => variables} =
               Graphyne.payload(document, %{"id" => "1", "after" => nil})

      assert text == document.text
      assert variables == %{"id" => "1"}
    end

    test "raises on a variable that the document does not declare" do
      document = compose(@query, [@fragment])

      assert_raise ArgumentError, ~s(Find declares no variables :after, "ID", it declares: "after", "id"), fn ->
        Graphyne.payload(document, %{"ID" => "1", after: nil})
      end
    end

    test "raises on a document with a missing fragment" do
      assert_raise ArgumentError, ~r/add them with compose\/2/, fn -> Graphyne.payload(@query, %{"id" => "1"}) end
    end
  end

  describe "result/1" do
    test "returns the data" do
      assert {:ok, %{"item" => %{"id" => "1"}}} = Graphyne.result(%{"data" => %{"item" => %{"id" => "1"}}})
      assert {:ok, %{}} = Graphyne.result(%{"data" => %{}, "errors" => []})
    end

    test "returns an error with the partial data" do
      errors = [%{"message" => "Timed out", "extensions" => %{"code" => "GATEWAY_TIMEOUT"}}]

      assert {:error, %Error{errors: ^errors, data: %{"item" => nil}}} =
               Graphyne.result(%{"data" => %{"item" => nil}, "errors" => errors})
    end

    test "returns an error without data" do
      assert {:error, %Error{data: nil}} = Graphyne.result(%{"errors" => [%{"message" => "Denied"}]})
    end

    test "returns a body that is not a GraphQL response" do
      assert {:error, "Bad gateway"} = Graphyne.result("Bad gateway")
      assert {:error, %{"error" => "invalid_token"}} = Graphyne.result(%{"error" => "invalid_token"})
    end
  end

  describe "Error" do
    test "matches codes and messages" do
      error = %Error{errors: [%{"message" => "Timed out", "extensions" => %{"code" => "GATEWAY_TIMEOUT"}}, %{}]}

      assert Error.code?(error, "GATEWAY_TIMEOUT")
      assert Error.code?(error, ["INTERNAL_SERVER_ERROR", "GATEWAY_TIMEOUT"])
      refute Error.code?(error, "FORBIDDEN")
      assert Error.message?(error, "Timed out")
      refute Error.message?(error, "Denied")
    end

    test "joins the messages" do
      error = %Error{errors: [%{"message" => "One"}, %{"message" => "Two"}]}

      assert Exception.message(error) == "One; Two"
    end
  end
end
