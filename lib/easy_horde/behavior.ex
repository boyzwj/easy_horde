defmodule EasyHorde.Behavior do
  @callback handle_init(map()) :: any()
  @callback handle_continue(any()) :: any()
  @callback handle_call(any(), any()) :: any()
  @callback handle_cast(any(), any()) :: any()
  @callback handle_info(any(), any()) :: any()
  @callback handle_terminate(any(), any()) :: any()
end
