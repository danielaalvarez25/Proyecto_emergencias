defmodule Emergencias.Dominio.Necesidad do
  @moduledoc "Solicitud de ayuda puntual asociada a una zona."

  @type tipo ::
          :agua
          | :alimentos
          | :medicamentos
          | :primeros_auxilios
          | :refugio
          | :transporte
          | :rescate
          | :otra

  @type prioridad :: :critica | :alta | :media | :baja

  @type estado :: :pendiente | :asignada | :en_atencion | :atendida | :cancelada

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          descripcion: String.t(),
          cantidad: pos_integer(),
          zona: String.t(),
          prioridad: prioridad(),
          responsable: String.t(),
          estado: estado(),
          asignaciones: [{String.t(), pos_integer()}]
        }

  @enforce_keys [:id, :tipo, :cantidad, :zona, :prioridad]
  defstruct id: nil,
            tipo: :otra,
            descripcion: "",
            cantidad: 0,
            zona: nil,
            prioridad: :media,
            responsable: "",
            estado: :pendiente,
            asignaciones: []
end
