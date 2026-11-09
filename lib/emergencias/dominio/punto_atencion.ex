defmodule Emergencias.Dominio.PuntoAtencion do
  @moduledoc "Punto de atención dentro de un sector (hoja de la jerarquía)."

  @type t :: %__MODULE__{
          nombre: String.t(),
          personas_estimadas: non_neg_integer()
        }

  @enforce_keys [:nombre]
  defstruct nombre: nil,
            personas_estimadas: 0
end
