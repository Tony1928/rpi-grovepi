defmodule GrovePi.Poller do
  @callback read_value(atom, GrovePi.pin) :: any

  defmacro __using__([default_trigger: default_trigger, read_type: read_type]) do
    quote location: :keep do
      use GenServer
      @behaviour GrovePi.Poller

      @poll_interval 100

      alias GrovePi.Registry.Pin

      alias GrovePi.Registry.Subscriber

      defmodule State do
        @moduledoc false
        defstruct [:pin, :trigger_state, :poll_interval, :prefix, :trigger, :poll_reference]
      end

      @doc """
      # Options

      * `:poll_interval` - The time in ms between polling for state.i If set to 0
                           polling will be turned off. Default: `100`
      * `:trigger` - This is used to pass in a trigger to use for triggering events. See specific poller for defaults
      * `:trigger_opts` - This is used to pass options to a trigger `init\1`. The default is `[]`
      """

      @spec start_link(GrovePi.pin) :: Supervisor.on_start
      def start_link(pin, opts \\ []) do
        poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)
        trigger = Keyword.get(opts, :trigger, unquote(default_trigger))
        trigger_opts = Keyword.get(opts, :trigger_opts, [])
        prefix = Keyword.get(opts, :prefix, Default)
        opts = Keyword.put(opts, :name, Pin.name(prefix, pin))

        GenServer.start_link(__MODULE__,
                             [pin, poll_interval, prefix, trigger, trigger_opts],
                             opts
                           )
      end

      def init([pin, poll_interval, prefix, trigger, trigger_opts]) do
        {:ok, trigger_state} = trigger.init(trigger_opts)
        state = %State{
          pin: pin,
          poll_interval: poll_interval,
          prefix: prefix,
          trigger: trigger,
          trigger_state: trigger_state,
        }

        state_with_poll_reference = schedule_poll(state)

        {:ok, state_with_poll_reference}
      end

      def schedule_poll(%{poll_interval: 0} = state), do: state

      def schedule_poll(%State{poll_interval: poll_interval} = state) do
        %{state | poll_reference: Process.send_after(self(), :poll_button, poll_interval)}
      end

      @doc """
        Stops polling immediately
      """
      @spec stop_polling(GrovePi.pin, atom) :: :ok
      def stop_polling(pin, prefix \\ Default) do
        GenServer.cast(Pin.name(prefix, pin), {:change_polling, 0})
      end

      @doc """
        Stops the current scheduled polling event and starts a new one with
        the new interval.
      """
      @spec change_polling(GrovePi.pin, integer, atom) :: :ok
      def change_polling(pin, interval, prefix \\ Default) do
        GenServer.cast(Pin.name(prefix, pin), {:change_polling, interval})
      end

      @spec read(GrovePi.pin, atom) :: unquote(read_type)
      def read(pin, prefix \\ Default) do
        GenServer.call(Pin.name(prefix, pin), :read)
      end

      @spec subscribe(GrovePi.pin, GrovePi.Trigger.event, atom) :: {:ok, pid} | {:error, {:already_registered, pid}}
      def subscribe(pin, event, prefix \\ Default) do
        Subscriber.subscribe(prefix, {pin, event})
      end

      def handle_cast({:change_polling, interval}, %State{poll_reference: poll_reference} = state) do
        Process.cancel_timer(poll_reference)
        {:noreply, schedule_poll(%{state | poll_interval: interval, poll_reference: nil}) }
      end

      def handle_call(:read, _from, state) do
        {value, new_state} = update_value(state)
        {:reply, value, new_state}
      end

      def handle_info(:poll_button, state) do
        {_, new_state} = update_value(state)
        schedule_poll(state)
        {:noreply, new_state}
      end

      @spec update_value(State) ::State
      defp update_value(state) do
        with value <- read_value(state.prefix, state.pin),
        trigger = {_, trigger_state} <- state.trigger.update(value, state.trigger_state),
        :ok <- notify(trigger, state.prefix, state.pin),
        do: {value, %{state | trigger_state: trigger_state}}
      end

      defp notify({:ok, _}, _, _) do
        :ok
      end

      defp notify({event, trigger_state}, prefix, pin) do
        Subscriber.notify_change(prefix, {pin, event, trigger_state})
      end
    end
  end
end
