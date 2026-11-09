defmodule Emergencias.Application do
  @moduledoc """
  Raíz del árbol de supervisión.

  Los hijos se agregan a medida que existan los procesos:

    * Persona A: GenServer de recursos, GenServer de albergues y un
      `DynamicSupervisor` para procesos por necesidad.
    * Persona B: GenServer de usuarios, zonas, personas y mascotas.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
