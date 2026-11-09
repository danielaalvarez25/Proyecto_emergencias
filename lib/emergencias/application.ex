defmodule Emergencias.Application do
  @moduledoc """
  Raíz del árbol de supervisión.

  Los hijos se agregan a medida que existan los procesos:

    * Persona A: `Emergencias.Recursos` y `Emergencias.Necesidades` (listos),
      GenServer de albergues y un `DynamicSupervisor`.
    * Persona B: GenServer de usuarios, zonas, personas y mascotas.

  `Recursos` va antes que `Necesidades` porque esta le pide inventario.
  """

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(hijos(), opts)
  end

  defp hijos do
    if Application.get_env(:emergencias, :iniciar_procesos, true) do
      [Emergencias.Recursos, Emergencias.Necesidades]
    else
      []
    end
  end
end
