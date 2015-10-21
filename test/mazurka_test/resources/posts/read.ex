defmodule MazurkaTest.Resources.Posts.Read do
  use Mazurka.Resource

  param post do
    Posts.get(value)
  end

  mediatype Mazurka.Mediatype.Hyperjson do
    action do
      %{
        "title" => post |> load() |> ^Map.get(:title),
        "null_title" => post |> ^Map.get(:title),
        "comments" => for comment <- post.comments do
          %{
            "title" => "comment #{comment}"
          }
        end
      }
    end
  end

  test "should respond to a request" do
    conn = request do
      params %{"post" => "123"}
    end

    assert conn.status == 200
    resp_body = Mazurka.Format.JSON.decode(conn.resp_body)
    assert length(resp_body["comments"]) > 1
    assert resp_body["title"] == "Hello!"
    assert resp_body["null_title"] == nil
  end
end
