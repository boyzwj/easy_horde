defmodule EasyHordeTest do
  use ExUnit.Case
  doctest EasyHorde

  # setup do
  #   nodes = LocalCluster.start_nodes("cluster#{:erlang.unique_integer()}", 2)
  # end

  test "start horde" do
    children = [MyHorde]
    opts = [strategy: :one_for_one, name: :test_sup]
    {:ok, pid} = Supervisor.start_link(children, opts)
    assert is_pid(pid) == true
  end
end
