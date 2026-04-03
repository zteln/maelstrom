defmodule MaelstromTest do
  use ExUnit.Case
  doctest Maelstrom

  test "greets the world" do
    assert Maelstrom.hello() == :world
  end
end
