defmodule LiveAttributeTest do
  use ExUnit.Case

  test "matches fun" do
    assert LiveAttribute.matches?(:_, :anyterm) == %{}
    assert LiveAttribute.matches?(:someterm, :anyterm) == false

    assert LiveAttribute.matches?({:update, Users, :_}, {:update, Users, :created}) == %{}
    assert LiveAttribute.matches?({:update, Users, :_}, {:update, Files, :created}) == false

    assert LiveAttribute.matches?([:update, Users, :_], [:update, Users, :created]) == %{}
    assert LiveAttribute.matches?([:update, Users, :_], {:update, Users, :created}) == false
    assert LiveAttribute.matches?([:update, Users, :_], [:update, Files, :created]) == false

    assert LiveAttribute.matches?({:update, [:_, Users], :_}, {:update, [31, Users], :created})
  end

  test "match extraction" do
    assert LiveAttribute.matches?(
             {:update, [:_, Users], {:"$", :action}},
             {:update, [31, Users], :created}
           ) == %{action: :created}

    assert LiveAttribute.matches?(
             {:update, [{:"$", :id}, Users], {:"$", :users}},
             {:update, [31, Users], :created}
           ) == %{users: :created, id: 31}
  end
end
