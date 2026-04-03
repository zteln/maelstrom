# Maelstrom

For usage with [Maelstrom](https://github.com/jepsen-io/maelstrom).

## Usage

Here is a simple example with the [Echo challenge](https://fly.io/dist-sys/1/).
First create an elixir script called `echo.exs` with content:
```elixir
Mix.install([{:maelstrom, path: "https://github.com/zteln/maelstrom"}])

defmodule Echo do
  use Maelstrom

  @impl Maelstrom
  def apply_msg(%{body: %{type: "echo"}} = msg, _opts) do
    put_in(msg, [:body, :type], "echo_ok")
  end
end

Echo.run()
Process.sleep(:infinity)
```
Then create a single binary file to run this script called `echo` with content:
```sh
DIRPATH=$(dirname $0)
cd $DIRPATH
elixir echo.exs
```
Then run with maelstrom:
```sh
./maelstrom test -w echo --bin echo --node-count 1 --time-limit 10
```
