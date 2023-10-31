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

      @impl true
      def handle_init(opts), do: opts

      @impl true
      def handle_continue(state), do: state

      @impl true
      def handle_terminate(_reason, _state), do: :ok

      @impl true
      def handle_info(_msg, state), do: state

      @impl true
      def handle_call(msg, state) do
        {{:error, :not_implemented}, state}
      end

      @impl true
      def handle_cast(msg, state), do: state

      defoverridable handle_terminate: 2,
                     handle_init: 1,
                     handle_continue: 1,
                     handle_info: 2,
                     handle_call: 2,
                     handle_cast: 2
    end
  end
end
