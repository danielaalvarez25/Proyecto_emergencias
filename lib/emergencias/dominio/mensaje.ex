defmodule Emergencias.Dominio.Mensaje do
  @moduledoc "Mensaje dirigido a una persona o familia."

  @type estado :: :pendiente | :entregado

  @type t :: %__MODULE__{
          id: String.t(),
          fecha: String.t(),
          remitente: String.t(),
          destinatario: String.t(),
          contenido: String.t(),
          estado: estado()
        }

  @enforce_keys [:id, :remitente, :destinatario, :contenido]
  defstruct id: nil,
            fecha: "",
            remitente: nil,
            destinatario: nil,
            contenido: "",
            estado: :pendiente
end
