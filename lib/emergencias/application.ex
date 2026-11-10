defmodule Emergencias.Application do
  @moduledoc """
  Raíz del árbol de supervisión.

  Los hijos se agregan a medida que existan los procesos:

    * Persona A: `Emergencias.Recursos`, `Emergencias.Necesidades` y
      `Emergencias.Albergues` (listos) y un `DynamicSupervisor` (pendiente).
    * Persona B: GenServer de usuarios, zonas, personas y mascotas.

  El orden importa: `Recursos` va primero porque `Necesidades` le pide
  inventario, y `Albergues` va al final porque consulta a ambos.
  """

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(hijos(), opts)
  end

  defp hijos do
    if Application.get_env(:emergencias, :iniciar_procesos, true) do
      [Emergencias.Recursos, Emergencias.Necesidades, Emergencias.Albergues]
    else
      []
    end
  end
end
