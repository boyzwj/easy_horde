defmodule EasyHorde.Worker do
  require Logger

  defmacro __using__(_opts) do
    quote location: :keep do
      @horde_registry_name __MODULE__
                           |> Module.split()
                           |> List.first()
                           |> Module.concat(:Registry)
      @horde_name __MODULE__ |> Module.split() |> Enum.take(1) |> Module.concat()
      use GenServer
      require Logger

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: via(opts.id))
      end

      def via(id) do
        {:via, Horde.Registry, {@horde_registry_name, {__MODULE__, id}}}
      end

      def child_spec(opts) do
        %{
          id: via(opts.id),
          start: {__MODULE__, :start_link, [opts]},
          shutdown: 1_000,
          restart: :transient,
          type: :worker
        }
      end

      @impl true
      def init(opts) do
        Process.flag(:trap_exit, true)
        state = @horde_name.handle_init(opts)
        {:ok, state, {:continue, :recovery_state}}
      end

      @impl true
      def handle_continue(:recovery_state, state) do
        state = @horde_name.handle_continue(state)
        {:noreply, state}
      end

      @impl true
      def handle_call(msg, _from, state) do
        {reply, state} =
          try do
            @horde_name.handle_call(msg, state)
          rescue
            e ->
              Logger.error("rpc error : #{inspect(e)}")
              {{:error, e}, state}
          end

        {:reply, reply, state}
      end

      @impl true
      def handle_info(msg, state) do
        state = @horde_name.handle_info(msg, state)
        {:noreply, state}
      end

      @impl true
      def handle_cast(msg, state) do
        state =
          try do
            @horde_name.handle_cast(msg, state)
          rescue
            e ->
              Logger.error("handel cast error : #{inspect(e)}")
              state
          end

        {:noreply, state}
      end

      @impl true
      def terminate(reason, state) do
        @horde_name.handle_terminate(reason, state)
      end
    end
  end
end
