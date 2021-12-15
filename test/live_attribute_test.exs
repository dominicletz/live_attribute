defmodule LiveAttributeTest do
  use ExUnit.Case

  test "greets the world" do
    assert LiveAttribute.matches?(:_, :anyterm)
    assert not LiveAttribute.matches?(:someterm, :anyterm)

    assert LiveAttribute.matches?({:update, Users, :_}, {:update, Users, :created})
    assert not LiveAttribute.matches?({:update, Users, :_}, {:update, Files, :created})

    assert LiveAttribute.matches?([:update, Users, :_], [:update, Users, :created])
    assert not LiveAttribute.matches?([:update, Users, :_], {:update, Users, :created})
    assert not LiveAttribute.matches?([:update, Users, :_], [:update, Files, :created])

    assert LiveAttribute.matches?({:update, [:_, Users], :_}, {:update, [31, Users], :created})
  end
end
