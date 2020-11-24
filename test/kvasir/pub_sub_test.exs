defmodule Kvasir.PubSubTest do
  use ExUnit.Case
  doctest Kvasir.PubSub

  test "greets the world" do
    assert Kvasir.PubSub.hello() == :world
  end
end
