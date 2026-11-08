defmodule Graphyne.TestTest do
  use ExUnit.Case, async: true
  use Graphyne

  import Graphyne.Test

  @fields ~GQL"fragment ItemFields on Item { id meta { tags } }"

  @query compose(
           ~GQL"""
           query Find($id: ID!) {
             item(id: $id) {
               ...ItemFields
               owner: user { name }
               ... on Book { pages }
               json
             }
           }
           """,
           [@fields]
         )

  describe "Graphyne.Syntax.shape/1" do
    test "merges fragments and inline fragments, and keys a field by its alias" do
      assert {:ok,
              %{
                "item" => %{
                  "id" => :leaf,
                  "meta" => %{"tags" => :leaf},
                  "owner" => %{"name" => :leaf},
                  "pages" => :leaf,
                  "json" => :leaf
                }
              }} = Graphyne.Syntax.shape(@query.text)
    end

    test "refuses a document with a missing fragment" do
      assert {:error, nil, "the document has no definition of the fragments F"} =
               Graphyne.Syntax.shape("query Q { ...F }")
    end
  end

  describe "assert_shape/2" do
    test "returns a body that only has selected fields" do
      body = %{
        "data" => %{
          "item" => [
            %{"id" => "1", "meta" => nil, "owner" => %{"name" => "A"}, "json" => %{"free" => "form"}},
            %{"id" => "2", "pages" => 10, "meta" => %{"tags" => ["x"]}}
          ]
        }
      }

      assert assert_shape(@query, body) == body
    end

    test "accepts a body with errors and no data" do
      body = %{"errors" => [%{"message" => "Denied"}]}

      assert assert_shape(@query, body) == body
    end

    test "lists each field that the query does not select" do
      body = %{
        "data" => %{
          "item" => [
            %{"id" => "1", "title" => "extra", "meta" => %{"tags" => [], "size" => 1}},
            %{"owner" => "not an object"}
          ]
        }
      }

      error = assert_raise ExUnit.AssertionError, fn -> assert_shape(@query, body) end

      assert error.message ==
               "Find does not select:\n  item[].meta.size\n  item[].title\n  item[].owner (a value, the query selects fields of it)"
    end

    test "takes the request body that Graphyne.payload/2 builds" do
      payload = Graphyne.payload(@query, %{"id" => "1"})

      assert ["item.name"] = shape_errors(payload, %{"data" => %{"item" => %{"name" => "x"}}})

      assert_raise ExUnit.AssertionError, ~r/Find does not select:\s+other/, fn ->
        assert_shape(payload, %{"data" => %{"other" => 1}})
      end
    end
  end
end
