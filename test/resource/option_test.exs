defmodule Test.Mazurka.Resource.Option do
  use Test.Mazurka.Case

  context Single do
    defmodule Foo do
      use Mazurka.Resource

      option foo

      mediatype Hyper do
        action do
          %{"foo" => foo}
        end
      end
    end
  after
    "action" ->
      {body, content_type, _} = Foo.action([], %{}, %{}, %{}, nil, %{foo: "123"})
      assert %{"foo" => "123"} == body
      assert {"application", "json", %{}} = content_type

    "action missing param" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{})
      assert %{"foo" => nil} = body
  end

  context Transform do
    defmodule Foo do
      use Mazurka.Resource

      option foo, fn(value) ->
        [value, value]
      end

      option bar, &[&1, &1]

      mediatype Hyper do
        action do
          %{
            "bar" => bar,
            "foo" => foo
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{}, nil, %{foo: "123", bar: "456"})
      assert %{"bar" => ["456", "456"], "foo" => ["123", "123"]} = body
  end

  context Referential do
    defmodule Foo do
      use Mazurka.Resource

      option foo

      option bar, fn(value) ->
        [foo, value]
      end

      mediatype Hyper do
        action do
          %{
            "bar" => bar
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{}, nil, %{foo: "123", bar: "456"})
      assert %{"bar" => ["123", "456"]} = body
  end
end
