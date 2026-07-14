defmodule Hawk.JsonApiAttributeTest.LocalizedPost do
  use Hawk.Model

  model "localized_posts" do
    field(:slug, :string)
    field(:translations, :map)
  end

  json_api do
    type("localized_posts")

    attribute(:slug, doc: "Stable slug.")
    attribute(:slug_copy, source: :slug, doc: "Source-backed copy of the slug.")

    attribute(:title,
      resolver: &Hawk.JsonApiAttributeTest.localized_title/2,
      doc: "Localized title."
    )
  end
end

defmodule Hawk.JsonApiAttributeTest.LocalizedPosts do
  def all(_opts) do
    [
      %Hawk.JsonApiAttributeTest.LocalizedPost{
        id: 1,
        slug: "north-sea",
        translations: %{
          "en" => %{"title" => "House by the sea"},
          "da" => %{"title" => "Hus ved havet"}
        }
      }
    ]
  end
end

defmodule Hawk.JsonApiAttributeTest.LocalizedPostsController do
  use Hawk.JsonApi.Controller,
    resource: Hawk.JsonApiAttributeTest.LocalizedPosts,
    model: Hawk.JsonApiAttributeTest.LocalizedPost
end

defmodule Hawk.JsonApiAttributeTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiAttributeTest.LocalizedPostsController

  def localized_title(post, opts) do
    locale = get_in(opts, [:context, :locale]) || "en"

    get_in(post.translations || %{}, [locale, "title"]) ||
      get_in(post.translations || %{}, ["en", "title"])
  end

  test "JSON:API attributes can be backed by source fields and context-aware resolvers" do
    post = %Hawk.JsonApiAttributeTest.LocalizedPost{
      id: 1,
      slug: "north-sea",
      translations: %{
        "en" => %{"title" => "House by the sea"},
        "da" => %{"title" => "Hus ved havet"}
      }
    }

    assert Hawk.JsonApi.document(post, context: %{locale: "da"}).data.attributes == %{
             slug: "north-sea",
             slug_copy: "north-sea",
             title: "Hus ved havet"
           }
  end

  test "resource contracts accept computed JSON:API attributes" do
    assert Hawk.ResourceContract.validate_model!(Hawk.JsonApiAttributeTest.LocalizedPost)
  end

  test "controllers pass request locale into JSON:API attribute resolvers" do
    conn = %{
      assigns: %{authority: Hawk.Authority.system()},
      req_headers: [{"x-locale", "da"}],
      resp_body: nil,
      status: nil
    }

    response = LocalizedPostsController.index(conn, %{})

    assert [%{attributes: %{title: "Hus ved havet"}}] = response.resp_body.data
  end

  test "controllers fall back to english locale when no locale headers are present" do
    conn = %{
      assigns: %{authority: Hawk.Authority.system()},
      req_headers: [],
      resp_body: nil,
      status: nil
    }

    response = LocalizedPostsController.index(conn, %{})

    assert [%{attributes: %{title: "House by the sea"}}] = response.resp_body.data
  end

  test "controllers fall back to accept-language when x-locale is missing" do
    conn = %{
      assigns: %{authority: Hawk.Authority.system()},
      req_headers: [{"accept-language", "da-DK,da;q=0.9,en;q=0.8"}],
      resp_body: nil,
      status: nil
    }

    response = LocalizedPostsController.index(conn, %{})

    assert [%{attributes: %{title: "Hus ved havet"}}] = response.resp_body.data
  end

  test "x-locale wins over accept-language and header names are matched case-insensitively" do
    conn = %{
      assigns: %{authority: Hawk.Authority.system()},
      req_headers: [{"X-Locale", "en"}, {"Accept-Language", "da-DK,da;q=0.9"}],
      resp_body: nil,
      status: nil
    }

    response = LocalizedPostsController.index(conn, %{})

    assert [%{attributes: %{title: "House by the sea"}}] = response.resp_body.data
  end
end
