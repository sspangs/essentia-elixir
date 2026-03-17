defmodule Essentia.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Define your supervision tree here
    ]

    opts = [strategy: :one_for_one, name: Essentia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
