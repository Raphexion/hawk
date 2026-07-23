defmodule Hawk.JsonApiAdapterDiscoveryTest.Author do
  use Hawk.Model

  model "adapter_discovery_authors" do
    field(:name, :string)
    has_many(:books, Hawk.JsonApiAdapterDiscoveryTest.Book)
  end
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Book do
  use Hawk.Model

  model "adapter_discovery_books" do
    field(:title, :string)
    belongs_to(:author, Hawk.JsonApiAdapterDiscoveryTest.Author)
  end
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Authors.Reader do
  def one(opts), do: {:one, opts}
  def all(opts), do: {:all, opts}
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Authors.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Authors.JsonApi do
  use Hawk.JsonApi.Resource

  type("authors")
  attribute(:name, doc: "Author name")
  relationship(:books, [])
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Authors.LiveView do
  def __hawk_live_view__, do: %{}
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Authors do
  use Hawk.Resource,
    model: Hawk.JsonApiAdapterDiscoveryTest.Author,
    writer: false
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Books.Reader do
  def one(opts), do: {:one, opts}
  def all(opts), do: {:all, opts}
  def filter_keys, do: MapSet.new([:id])
  def filter_handlers, do: %{}
  def preload_keys, do: MapSet.new([:author])
  def sort_keys, do: MapSet.new([:id])
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Books.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Books.JsonApi do
  use Hawk.JsonApi.Resource

  type("books")
  attribute(:title, doc: "Book title")
  relationship(:author, [])
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Books.LiveView do
  def __hawk_live_view__, do: %{}
end

defmodule Hawk.JsonApiAdapterDiscoveryTest.Books do
  use Hawk.Resource,
    model: Hawk.JsonApiAdapterDiscoveryTest.Book,
    writer: false
end

defmodule Hawk.JsonApiAdapterDiscoveryTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiAdapterDiscoveryTest.{Author, Book}

  test "metadata uses the sibling JSON:API adapter discovered from the model resource" do
    assert Hawk.JsonApi.metadata(Author).type == "authors"
    assert Map.has_key?(Hawk.JsonApi.metadata(Author).attributes, :name)

    assert Hawk.JsonApi.openapi_schema(Author)["properties"]["name"] == %{
             "description" => "Author name"
           }
  end

  test "resource contracts use sibling JSON:API adapter metadata" do
    assert :ok = Hawk.ResourceContract.validate!(Hawk.JsonApiAdapterDiscoveryTest.Books, Book)
  end

  test "included relationship resources render with their own discovered adapter metadata" do
    book = %Book{
      id: Videdal.course_id(),
      title: "The Schema",
      author_id: Videdal.parent_id(),
      author: %Author{id: Videdal.parent_id(), name: "Ada"}
    }

    assert Hawk.JsonApi.document(book, preloads: [:author]) == %{
             data: %{
               type: "books",
               id: Videdal.course_id(),
               attributes: %{title: "The Schema"},
               relationships: %{author: %{data: %{type: "authors", id: Videdal.parent_id()}}}
             },
             included: [
               %{
                 type: "authors",
                 id: Videdal.parent_id(),
                 attributes: %{name: "Ada"},
                 relationships: %{books: %{data: []}}
               }
             ]
           }
  end
end
