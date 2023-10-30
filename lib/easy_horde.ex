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

defmodule EasyHorde.Behavior do
  @callback handle_init(map()) :: any()
  @callback handle_continue(any()) :: any()
  @callback handle_call(any(), any()) :: any()
  @callback handle_cast(any(), any()) :: any()
  @callback handle_info(any(), any()) :: any()
  @callback handle_terminate(any(), any()) :: any()
end

defmodule EasyHorde do
  defmacro __using__(opts) do
    quote location: :keep do
      use Supervisor
      require Logger
      @type options() :: [option()]
      @type option :: {:worker_num, non_neg_integer()}

      @worker_num unquote(opts[:worker_num])
      @worker_name Module.concat(__MODULE__, :Worker)
      @horde_name __MODULE__
      @horde_registry_name Module.concat(__MODULE__, :Registry)
      @horde_supervisor_name Module.concat(__MODULE__, :Supervisor)
      @horde_connector_name Module.concat(__MODULE__, :ClusterConnector)
      @behaviour EasyHorde.Behavior

      defmodule Module.concat(__MODULE__, :Worker) do
        use EasyHorde.Worker, unquote(opts)
      end

      def start_link(args) do
        Supervisor.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          {Horde.Registry, [name: @horde_registry_name, keys: :unique, members: :auto]},
          {
            Horde.DynamicSupervisor,
            [
              name: @horde_supervisor_name,
              shutdown: 1_000,
              strategy: :one_for_one,
              distribution_strategy: Horde.UniformQuorumDistribution,
              max_restarts: 100_000,
              max_seconds: 1,
              members: :auto,
              process_redistribution: :active
            ]
          },
          %{
            id: @horde_connector_name,
            restart: :transient,
            start:
              {Agent, :start,
               [
                 fn ->
                   Horde.DynamicSupervisor.wait_for_quorum(@horde_supervisor_name, 30_000)

                   1..@worker_num
                   |> Enum.map(&@worker_name.child_spec(%{id: &1}))
                   |> Enum.each(&Horde.DynamicSupervisor.start_child(@horde_supervisor_name, &1))
                 end
               ]}
          }
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp choose_worker(key) do
        (:erlang.phash2(key, @worker_num) + 1) |> @worker_name.via()
      end

      @spec call(any(), any()) :: :any
      def call(msg, key \\ 0) do
        choose_worker(key) |> GenServer.call(msg)
      end

      @spec cast(any(), any()) :: :ok
      def cast(msg, key \\ 0) do
        choose_worker(key) |> GenServer.cast(msg)
      end

      def handle_init(opts), do: opts

      def handle_terminate(_reason, _state), do: :ok

      def handle_info(_msg, state), do: state

      defoverridable handle_terminate: 2, handle_init: 1, handle_info: 2
    end
  end
end
