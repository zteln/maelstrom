defmodule Maelstrom do
  @moduledoc """
  Injects `run/0` into the calling module and requires a callback `apply_msg/2`.
  `apply_msg/2` receives a message from the Maelstrom binary as the first argument, and a keyword list as the second. The keyword list `opts` contains `:owner` which is the PID of the calling module.
  """
  defstruct [
    :owner,
    :m_f,
    :node_id,
    :node_ids
  ]

  @callback apply_msg(msg :: map(), opts :: keyword()) :: map()

  defmacro __using__(opts) do
    quote do
      @behaviour unquote(__MODULE__)

      def run() do
        owner = self()
        m_f = {__MODULE__, :apply_msg}

        Task.start_link(fn ->
          IO.stream()
          |> Stream.transform(
            %Maelstrom{m_f: m_f, owner: owner},
            fn input, state ->
              debug_msg(input)
              state = Maelstrom.process_input(state, input)
              {[], state}
            end
          )
          |> Stream.run()
        end)
      end

      if unquote(opts[:debug]) do
        defp debug_msg(input) do
          unquote(opts[:debug_file] || Path.join(File.cwd!(), "maelstrom.log"))
          |> File.write!(input, [:append])
        end
      else
        defp debug_msg(input), do: :ok
      end
    end
  end

  def process_input(state, input) do
    msg = decode(input)
    {reply, state} = process_msg(state, msg)

    reply
    |> encode()
    |> send_reply()

    state
  end

  # initialize Maelstrom
  defp process_msg(state, %{body: %{type: "init"}} = msg) do
    %{
      body:
        %{
          node_id: node_id,
          node_ids: node_ids
        } = body
    } = msg

    body = Map.put(body, :type, "init_ok")
    reply = %{msg | body: body} |> prepare()
    {reply, %{state | node_id: node_id, node_ids: node_ids}}
  end

  # let client handle all other messages
  defp process_msg(state, msg) do
    %{m_f: {mod, fun}} = state
    opts = [owner: state.owner, node_id: state.node_id, node_ids: state.node_ids]
    args = [msg, opts]

    reply =
      apply(mod, fun, args)
      |> prepare()

    {reply, state}
  end

  defp send_reply(reply) do
    IO.puts(reply)
  end

  defp prepare(msg) do
    %{src: src, dest: dest, body: %{msg_id: msg_id} = body} = msg
    body = Map.put(body, :in_reply_to, msg_id)
    %{src: dest, dest: src, body: body}
  end

  defp decode(input) do
    {decoded, _acc, _bin} =
      JSON.decode(input, :ok,
        object_push: fn key, value, acc -> [{String.to_atom(key), value} | acc] end
      )

    decoded
  end

  defp encode(term), do: JSON.encode!(term)
end
