defmodule EasyHordeTest do
  use ExUnit.Case
  doctest EasyHorde

  test "greets the world" do
    assert EasyHorde.hello() == :world
  end
end
