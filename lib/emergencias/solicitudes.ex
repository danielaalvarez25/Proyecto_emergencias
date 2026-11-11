defmodule Emergencias.Solicitudes do
  @moduledoc """
  Lógica pura de las necesidades puntuales (sin procesos ni archivos).

  Trabaja sobre un mapa `%{id => %Necesidad{}}` y nunca lo modifica: cada
  operación devuelve un mapa nuevo. El GenServer `Emergencias.Necesidades`
  se ocupa de serializar el acceso y de persistir.

  Estados y transiciones válidas:

      pendiente   -> asignada | cancelada
      asignada    -> en_atencion | atendida | cancelada
      en_atencion -> atendida | cancelada
      atendida    -> (cerrada)
      cancelada   -> (cerrada)

  Una necesidad cerrada (atendida o cancelada) no puede cambiar de estado
  ni volver a consumir recursos.
  """

  alias Emergencias.Dominio.Necesidad

  @tipos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  # De mayor a menor urgencia: el orden de la lista ES el orden de atención.
  @prioridades [:critica, :alta, :media, :baja]

  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :atendida, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  @type mapa :: %{optional(String.t()) => Necesidad.t()}

  def tipos, do: @tipos
  def prioridades, do: @prioridades
  def estados, do: @estados

  # --- Registro -------------------------------------------------------

  @doc """
  Registra una necesidad con identificador único generado (`N001`, `N002`...).
  `tipo`, `prioridad` y `estado` aceptan átomos o texto (`"Crítica"`, `"en atención"`).
  """
  @spec registrar(mapa(), term(), term(), term(), term(), term(), term()) ::
          {:ok, Necesidad.t(), mapa()} | {:error, atom()}
  def registrar(mapa, tipo, cantidad, prioridad, zona, descripcion \\ "", responsable \\ "") do
    with {:ok, tipo} <- convertir(tipo, @tipos, :tipo_invalido),
         {:ok, prioridad} <- convertir(prioridad, @prioridades, :prioridad_invalida),
         :ok <- validar_cantidad(cantidad),
         :ok <- validar_texto(zona, :zona_invalida),
         :ok <- validar_opcional(descripcion),
         :ok <- validar_opcional(responsable) do
      id = siguiente_id(mapa)

      necesidad = %Necesidad{
        id: id,
        tipo: tipo,
        descripcion: String.trim(descripcion),
        cantidad: cantidad,
        zona: String.trim(zona),
        prioridad: prioridad,
        responsable: String.trim(responsable),
        estado: :pendiente,
        asignaciones: []
      }

      {:ok, necesidad, Map.put(mapa, id, necesidad)}
    end
  end

  @doc "Siguiente identificador libre: el mayor número usado más uno."
  @spec siguiente_id(mapa()) :: String.t()
  def siguiente_id(mapa) do
    maximo = mapa |> Map.keys() |> Enum.map(&numero_id/1) |> Enum.max(fn -> 0 end)
    "N" <> String.pad_leading(Integer.to_string(maximo + 1), 3, "0")
  end

  defp numero_id("N" <> resto) do
    case Integer.parse(resto) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp numero_id(_otro), do: 0

  @doc "Busca una necesidad por id (sin distinguir mayúsculas)."
  @spec obtener(mapa(), term()) :: {:ok, Necesidad.t()} | {:error, :no_existe}
  def obtener(mapa, id) do
    clave = id |> to_string() |> String.trim() |> String.upcase()

    case Map.fetch(mapa, clave) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, :no_existe}
    end
  end

  # --- Estados --------------------------------------------------------

  @doc "Cambia el estado respetando las transiciones válidas."
  @spec cambiar_estado(mapa(), term(), term()) ::
          {:ok, Necesidad.t(), mapa()} | {:error, atom()}
  def cambiar_estado(mapa, id, nuevo) do
    with {:ok, necesidad} <- obtener(mapa, id),
         {:ok, nuevo} <- convertir(nuevo, @estados, :estado_invalido),
         :ok <- validar_transicion(necesidad.estado, nuevo) do
      actualizada = %{necesidad | estado: nuevo}
      {:ok, actualizada, Map.put(mapa, actualizada.id, actualizada)}
    end
  end

  defp validar_transicion(actual, nuevo) do
    cond do
      actual in [:atendida, :cancelada] -> {:error, :necesidad_cerrada}
      nuevo in Map.fetch!(@transiciones, actual) -> :ok
      true -> {:error, :transicion_invalida}
    end
  end

  # --- Asignación de recursos -----------------------------------------

  @doc """
  Verifica que se pueda asignar `cantidad` a la necesidad: debe estar
  pendiente y la cantidad no puede exceder lo que aún le falta.
  Se llama ANTES de descontar inventario.
  """
  @spec puede_asignar(mapa(), term(), term()) :: {:ok, Necesidad.t()} | {:error, atom()}
  def puede_asignar(mapa, id, cantidad) do
    with {:ok, necesidad} <- obtener(mapa, id),
         :ok <- validar_abierta(necesidad),
         :ok <- validar_cantidad(cantidad),
         :ok <- validar_restante(necesidad, cantidad) do
      {:ok, necesidad}
    end
  end

  @doc """
  Anota las partes `[{codigo_recurso, cantidad}]` ya tomadas del inventario.
  Si la necesidad queda cubierta pasa a `:asignada`; si no, sigue `:pendiente`.
  """
  @spec aplicar_asignacion(mapa(), term(), [{String.t(), pos_integer()}]) ::
          {:ok, Necesidad.t(), mapa()} | {:error, atom()}
  def aplicar_asignacion(mapa, id, partes) do
    with {:ok, necesidad} <- obtener(mapa, id) do
      cubierta = %{necesidad | asignaciones: necesidad.asignaciones ++ partes}
      estado = if restante(cubierta) <= 0, do: :asignada, else: necesidad.estado
      actualizada = %{cubierta | estado: estado}
      {:ok, actualizada, Map.put(mapa, actualizada.id, actualizada)}
    end
  end

  @doc "Cantidad ya asignada a la necesidad (suma recursiva de sus asignaciones)."
  @spec asignado(Necesidad.t()) :: non_neg_integer()
  def asignado(necesidad), do: sumar(necesidad.asignaciones, 0)

  defp sumar([], acumulado), do: acumulado
  defp sumar([{_codigo, cantidad} | resto], acumulado), do: sumar(resto, acumulado + cantidad)

  @doc "Cantidad que aún le falta a la necesidad."
  @spec restante(Necesidad.t()) :: integer()
  def restante(necesidad), do: necesidad.cantidad - asignado(necesidad)

  defp validar_abierta(%{estado: estado}) when estado in [:atendida, :cancelada],
    do: {:error, :necesidad_cerrada}

  defp validar_abierta(%{estado: :pendiente}), do: :ok
  defp validar_abierta(_otra), do: {:error, :ya_asignada}

  defp validar_restante(necesidad, cantidad) do
    if cantidad <= restante(necesidad), do: :ok, else: {:error, :excede_necesidad}
  end

  # --- Consultas y prioridad ------------------------------------------

  @doc """
  Consulta necesidades. Filtros opcionales (keyword): `:zona`, `:tipo`,
  `:prioridad`, `:estado`. El resultado sale ordenado por prioridad.
  """
  @spec consultar(mapa(), keyword()) :: [Necesidad.t()]
  def consultar(mapa, filtros \\ []) do
    mapa
    |> Map.values()
    |> Enum.filter(&cumple_filtros?(&1, filtros))
    |> ordenar_por_prioridad()
  end

  @doc "Necesidades pendientes, de la más urgente a la menos urgente."
  @spec pendientes(mapa()) :: [Necesidad.t()]
  def pendientes(mapa), do: consultar(mapa, estado: :pendiente)

  @doc "Ordena por prioridad (crítica primero) y, a igual prioridad, por id."
  @spec ordenar_por_prioridad([Necesidad.t()]) :: [Necesidad.t()]
  def ordenar_por_prioridad(necesidades) do
    Enum.sort_by(necesidades, &{rango(&1.prioridad), &1.id})
  end

  defp rango(prioridad), do: Enum.find_index(@prioridades, &(&1 == prioridad))

  @doc """
  Planifica la atención: recorre las necesidades (ya ordenadas por
  prioridad) y reserva para cada una lo que le falta mientras alcance el
  inventario de su tipo; si no alcanza, la salta y sigue con la siguiente.

  `disponibles` es `%{"agua" => 50, ...}`. Devuelve `[{id, recurso, cantidad}]`
  en orden de atención. Recursiva sobre la lista de necesidades.
  """
  @spec planificar([Necesidad.t()], %{optional(String.t()) => non_neg_integer()}) ::
          [{String.t(), String.t(), pos_integer()}]
  def planificar(necesidades, disponibles), do: planificar(necesidades, disponibles, [])

  defp planificar([], _disponibles, acumulado), do: Enum.reverse(acumulado)

  defp planificar([necesidad | resto], disponibles, acumulado) do
    recurso = Atom.to_string(necesidad.tipo)
    falta = restante(necesidad)
    hay = Map.get(disponibles, recurso, 0)

    if falta > 0 and hay >= falta do
      planificar(resto, Map.put(disponibles, recurso, hay - falta), [
        {necesidad.id, recurso, falta} | acumulado
      ])
    else
      planificar(resto, disponibles, acumulado)
    end
  end

  defp cumple_filtros?(necesidad, filtros) do
    Enum.all?(filtros, fn
      {:zona, valor} -> normalizar(necesidad.zona) == normalizar(valor)
      {:tipo, valor} -> coincide?(necesidad.tipo, valor, @tipos)
      {:prioridad, valor} -> coincide?(necesidad.prioridad, valor, @prioridades)
      {:estado, valor} -> coincide?(necesidad.estado, valor, @estados)
      _otro -> true
    end)
  end

  defp coincide?(actual, valor, validos) do
    case convertir(valor, validos, :invalido) do
      {:ok, atomo} -> atomo == actual
      {:error, _razon} -> false
    end
  end

  # --- Conversión a filas de texto ------------------------------------

  @doc "Convierte una necesidad en la fila que guarda `Storage`."
  @spec a_fila(Necesidad.t()) :: [term()]
  def a_fila(necesidad) do
    [
      necesidad.id,
      necesidad.tipo,
      necesidad.descripcion,
      necesidad.cantidad,
      necesidad.zona,
      necesidad.prioridad,
      necesidad.responsable,
      necesidad.estado,
      Enum.map_join(necesidad.asignaciones, ";", fn {codigo, cantidad} ->
        "#{codigo}:#{cantidad}"
      end)
    ]
  end

  @doc "Reconstruye una necesidad desde su fila. Una fila dañada devuelve `:error`."
  @spec desde_fila([String.t()]) :: {:ok, Necesidad.t()} | :error
  def desde_fila([id, tipo, descripcion, cantidad, zona, prioridad, responsable, estado, asignaciones]) do
    with {:ok, tipo} <- convertir(tipo, @tipos, :error),
         {:ok, prioridad} <- convertir(prioridad, @prioridades, :error),
         {:ok, estado} <- convertir(estado, @estados, :error),
         {n, ""} when n > 0 <- Integer.parse(cantidad),
         {:ok, asignaciones} <- decodificar_asignaciones(String.split(asignaciones, ";", trim: true), []) do
      {:ok,
       %Necesidad{
         id: id,
         tipo: tipo,
         descripcion: descripcion,
         cantidad: n,
         zona: zona,
         prioridad: prioridad,
         responsable: responsable,
         estado: estado,
         asignaciones: asignaciones
       }}
    else
      _ -> :error
    end
  end

  def desde_fila(_otra), do: :error

  # Recursiva sobre la lista de partes "codigo:cantidad".
  defp decodificar_asignaciones([], acumulado), do: {:ok, Enum.reverse(acumulado)}

  defp decodificar_asignaciones([parte | resto], acumulado) do
    with [codigo, cantidad] <- String.split(parte, ":"),
         {n, ""} when n > 0 <- Integer.parse(cantidad) do
      decodificar_asignaciones(resto, [{codigo, n} | acumulado])
    else
      _ -> :error
    end
  end

  # --- Validaciones ---------------------------------------------------

  defp convertir(valor, validos, razon) when is_atom(valor) or is_binary(valor) do
    buscado = normalizar(valor)

    case Enum.find(validos, &(Atom.to_string(&1) == buscado)) do
      nil -> {:error, razon}
      atomo -> {:ok, atomo}
    end
  end

  defp convertir(_valor, _validos, razon), do: {:error, razon}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_cantidad), do: {:error, :cantidad_invalida}

  defp validar_texto(texto, razon) do
    if is_binary(texto) and String.trim(texto) != "", do: :ok, else: {:error, razon}
  end

  defp validar_opcional(texto) when is_binary(texto), do: :ok
  defp validar_opcional(_otro), do: {:error, :datos_invalidos}

  # Minúsculas, sin tildes y con espacios como guion bajo:
  # "En Atención" -> "en_atencion".
  defp normalizar(texto) do
    texto
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/, "_")
  end
end
