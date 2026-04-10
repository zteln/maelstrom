defmodule Maelstrom do
  @moduledoc false

  defstruct [
    :src,
    :dest,
    :node_id,
    :node_ids,
    :in_msg_id,
    waiting_rpcs: %{},
    msg_id: 0
  ]

  @type t :: %__MODULE__{}

  @callback init_state() :: any()
  @callback handle_msg(
              body :: map(),
              state :: any(),
              meta :: map()
            ) ::
              {:noreply, any()}
              | {:noreply, any(), t()}
              | {:reply, map(), any()}
              | {:reply, map(), any(), t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      use Agent

      @impl Maelstrom
      def handle_msg(%{type: "init"} = body, state, meta) do
        meta = %{meta | node_id: body.node_id, node_ids: body.node_ids}
        body = %{type: "init_ok"}
        {:reply, body, state, meta}
      end

      def handle_msg(%{in_reply_to: msg_id} = resp_body, state, meta) do
        %{waiting_rpcs: waiting_rpcs} = meta

        case Map.pop(waiting_rpcs, msg_id) do
          {nil, _waiting_rpcs} ->
            {:noreply, state}

          {{resp_callback, body}, waiting_rpcs} ->
            meta = %{meta | waiting_rpcs: waiting_rpcs}
            resp_callback.(body, resp_body, state, meta)
        end
      end
    end
  end

  defmacro __before_compile__(_opts) do
    quote do
      def handle_msg(_body, state, _meta) do
        {:noreply, state}
      end
    end
  end

  @doc "Starts an Agent process that starts that stdio streamer."
  def start_link(mod) do
    Agent.start_link(fn ->
      me = self()
      state = mod.init_state()
      meta = %__MODULE__{}

      start_io_stream(fn msg ->
        msg = decode(msg)

        Agent.update(me, fn {state, meta} ->
          meta = %{
            meta
            | src: msg.src,
              dest: msg.dest,
              in_msg_id: get_in(msg, [:body, :msg_id])
          }

          {body, state, meta} =
            case mod.handle_msg(msg.body, state, meta) do
              {:noreply, state} -> {nil, state, meta}
              {:noreply, state, meta} -> {nil, state, meta}
              {:reply, reply, state} -> {reply, state, meta}
              {:reply, reply, state, meta} -> {reply, state, meta}
            end

          if body do
            body
            |> into_reply(meta)
            |> encode()
            |> write_to_stdout()
          end

          {state, %{meta | msg_id: meta.msg_id + 1}}
        end)
      end)

      {state, meta}
    end)
  end

  @doc "Sends a fire-and-forget message."
  def cast(src, dest, body, meta) do
    %{src: src, dest: dest, body: body}
    |> encode()
    |> write_to_stdout()

    meta
  end

  @doc "Sends an RPC message, expecting a reply."
  def call(src, dest, body, response_callback, meta) do
    body = Map.put(body, :msg_id, meta.msg_id)

    %{src: src, dest: dest, body: body}
    |> encode()
    |> write_to_stdout()

    waiting_rpcs = Map.put(meta.waiting_rpcs, meta.msg_id, response_callback)

    %{meta | msg_id: meta.msg_id + 1, waiting_rpcs: waiting_rpcs}
  end

  @doc "Writes the term to STDERR, returning the unchanged argument."
  def debug(term) do
    term
    |> encode()
    |> write_to_stderr()

    term
  end

  defp start_io_stream(callback) do
    Task.start_link(fn ->
      IO.stream()
      |> Stream.each(&callback.(&1))
      |> Stream.run()
    end)
  end

  defp into_reply(body, meta) do
    body =
      body
      |> Map.put(:in_reply_to, meta.in_msg_id)
      |> Map.put(:msg_id, meta.msg_id)

    %{
      src: meta.dest,
      dest: meta.src,
      body: body
    }
  end

  defp decode(input) do
    {decoded, _acc, _bin} =
      JSON.decode(input, :ok,
        object_push: fn key, value, acc -> [{String.to_atom(key), value} | acc] end
      )

    decoded
  end

  defp encode(term), do: JSON.encode!(term)

  defp write_to_stdout(term), do: IO.puts(term)
  defp write_to_stderr(term), do: IO.warn(term)
end
