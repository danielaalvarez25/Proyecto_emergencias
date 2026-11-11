defmodule Emergencias.Application do
  @moduledoc """
  Raíz del árbol de supervisión.

  Los hijos se agregan a medida que existan los procesos:

    * Persona A: `Emergencias.Recursos`, `Emergencias.Necesidades`,
      `Emergencias.Albergues` y `Emergencias.Despacho` (DynamicSupervisor).
    * Persona B: GenServer de usuarios, zonas, personas y mascotas.

  El orden importa: `Recursos` va primero porque `Necesidades` le pide
  inventario, `Albergues` consulta a ambos y `Despacho` va al final porque
  sus procesos llaman a `Necesidades`.
  """

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(hijos(), opts)
  end

  defp hijos do
    if Application.get_env(:emergencias, :iniciar_procesos, true) do
      [
        Emergencias.Recursos,
        Emergencias.Necesidades,
        Emergencias.Albergues,
        Emergencias.Despacho
      ]
    else
      []
    end
  end
end
