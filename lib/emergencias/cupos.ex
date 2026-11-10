defmodule Emergencias.Cupos do
  @moduledoc """
  Lógica pura de los albergues (sin procesos ni archivos).

  Trabaja sobre un mapa `%{codigo => %Albergue{}}` y nunca lo modifica:
  cada operación devuelve un mapa nuevo. El GenServer `Emergencias.Albergues`
  serializa el acceso y persiste.

  Reglas: la ocupación nunca supera la capacidad, una persona no puede
  estar en dos albergues a la vez y los códigos no se repiten. Los códigos
  se guardan en mayúsculas (`a01` y `A01` son el mismo albergue).
  """

  alias Emergencias.Dominio.Albergue

  @type mapa :: %{optional(String.t()) => Albergue.t()}

  # --- Registro y consulta --------------------------------------------

  @doc """
  Registra un albergue. `ocupacion` es la ocupación inicial (personas ya
  alojadas sin documento registrado); por defecto 0.
  """
  @spec registrar(mapa(), term(), term(), term(), term(), term()) ::
          {:ok, Albergue.t(), mapa()} | {:error, atom()}
  def registrar(mapa, codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    with {:ok, codigo} <- normalizar_codigo(codigo),
         :ok <- validar_texto(nombre),
         :ok <- validar_texto(zona),
         :ok <- validar_capacidad(capacidad),
         :ok <- validar_ocupacion(ocupacion, capacidad),
         :ok <- validar_libre(mapa, codigo) do
      albergue = %Albergue{
        codigo: codigo,
        nombre: String.trim(nombre),
        zona: String.trim(zona),
        capacidad: capacidad,
        ocupacion: ocupacion
      }

      {:ok, albergue, Map.put(mapa, codigo, albergue)}
    end
  end

  @doc "Busca un albergue por código (sin distinguir mayúsculas)."
  @spec obtener(mapa(), term()) :: {:ok, Albergue.t()} | {:error, :no_existe}
  def obtener(mapa, codigo) do
    clave = codigo |> to_string() |> String.trim() |> String.upcase()

    case Map.fetch(mapa, clave) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, :no_existe}
    end
  end

  @doc "Lista albergues ordenados por código. Filtro opcional: `zona: \"...\"`."
  @spec listar(mapa(), keyword()) :: [Albergue.t()]
  def listar(mapa, filtros \\ []) do
    mapa
    |> Map.values()
    |> Enum.filter(fn albergue ->
      Enum.all?(filtros, fn
        {:zona, valor} -> minusculas(albergue.zona) == minusculas(valor)
        _otro -> true
      end)
    end)
    |> Enum.sort_by(& &1.codigo)
  end

  @doc "Cupos libres de un albergue."
  @spec cupos(Albergue.t()) :: non_neg_integer()
  def cupos(albergue), do: albergue.capacidad - albergue.ocupacion

  @doc "Porcentaje de ocupación (0.0 a 100.0). Un albergue sin capacidad cuenta como 0.0."
  @spec porcentaje(Albergue.t()) :: float()
  def porcentaje(%{capacidad: 0}), do: 0.0
  def porcentaje(albergue), do: Float.round(albergue.ocupacion * 100 / albergue.capacidad, 1)

  @doc "Resumen listo para mostrar."
  @spec resumen(Albergue.t()) :: map()
  def resumen(albergue) do
    %{
      codigo: albergue.codigo,
      nombre: albergue.nombre,
      zona: albergue.zona,
      capacidad: albergue.capacidad,
      ocupacion: albergue.ocupacion,
      cupos: cupos(albergue),
      porcentaje: porcentaje(albergue),
      recursos: albergue.recursos,
      necesidades: albergue.necesidades
    }
  end

  @doc "Los `limite` albergues con mayor porcentaje de ocupación (desempata por código)."
  @spec mayor_ocupacion(mapa(), pos_integer()) :: [Albergue.t()]
  def mayor_ocupacion(mapa, limite \\ 3) do
    mapa
    |> Map.values()
    |> Enum.sort_by(&{-porcentaje(&1), &1.codigo})
    |> Enum.take(limite)
  end

  @doc "Código del albergue donde está alojada la persona, o `:ninguno`."
  @spec donde_esta(mapa(), term()) :: {:ok, String.t()} | :ninguno
  def donde_esta(mapa, documento), do: buscar(Map.values(mapa), to_string(documento) |> String.trim())

  # Recursiva sobre la lista de albergues.
  defp buscar([], _documento), do: :ninguno

  defp buscar([albergue | resto], documento) do
    if MapSet.member?(albergue.personas, documento) do
      {:ok, albergue.codigo}
    else
      buscar(resto, documento)
    end
  end

  # --- Ingreso y salida -----------------------------------------------

  @doc "Registra el ingreso de una persona. Nunca supera la capacidad."
  @spec ingresar(mapa(), term(), term()) :: {:ok, Albergue.t(), mapa()} | {:error, atom()}
  def ingresar(mapa, codigo, documento) do
    with {:ok, albergue} <- obtener(mapa, codigo),
         {:ok, documento} <- validar_documento(documento),
         :ok <- validar_no_alojada(mapa, albergue, documento),
         :ok <- validar_cupo(albergue) do
      actualizado = %{
        albergue
        | ocupacion: albergue.ocupacion + 1,
          personas: MapSet.put(albergue.personas, documento)
      }

      {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}
    end
  end

  @doc "Registra la salida de una persona alojada en ese albergue."
  @spec salir(mapa(), term(), term()) :: {:ok, Albergue.t(), mapa()} | {:error, atom()}
  def salir(mapa, codigo, documento) do
    with {:ok, albergue} <- obtener(mapa, codigo),
         {:ok, documento} <- validar_documento(documento),
         :ok <- validar_alojada(albergue, documento) do
      actualizado = %{
        albergue
        | ocupacion: albergue.ocupacion - 1,
          personas: MapSet.delete(albergue.personas, documento)
      }

      {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}
    end
  end

  defp validar_no_alojada(mapa, albergue, documento) do
    case donde_esta(mapa, documento) do
      :ninguno -> :ok
      {:ok, codigo} when codigo == albergue.codigo -> {:error, :persona_ya_registrada}
      {:ok, _otro} -> {:error, :persona_en_otro_albergue}
    end
  end

  defp validar_alojada(albergue, documento) do
    if MapSet.member?(albergue.personas, documento),
      do: :ok,
      else: {:error, :persona_no_registrada}
  end

  defp validar_cupo(albergue) do
    if cupos(albergue) > 0, do: :ok, else: {:error, :albergue_lleno}
  end

  # --- Asociaciones ---------------------------------------------------

  @doc "Asocia un recurso (por código) al albergue."
  @spec asociar_recurso(mapa(), term(), term()) :: {:ok, Albergue.t(), mapa()} | {:error, atom()}
  def asociar_recurso(mapa, codigo, recurso) do
    asociar(mapa, codigo, recurso, :recursos)
  end

  @doc "Asocia una necesidad (por id) al albergue."
  @spec asociar_necesidad(mapa(), term(), term()) :: {:ok, Albergue.t(), mapa()} | {:error, atom()}
  def asociar_necesidad(mapa, codigo, necesidad) do
    asociar(mapa, codigo, necesidad, :necesidades)
  end

  defp asociar(mapa, codigo, elemento, campo) do
    with {:ok, albergue} <- obtener(mapa, codigo),
         :ok <- validar_texto(elemento) do
      elemento = String.trim(elemento)

      if elemento in Map.fetch!(albergue, campo) do
        {:error, :ya_asociado}
      else
        actualizado = Map.update!(albergue, campo, &(&1 ++ [elemento]))
        {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}
      end
    end
  end

  # --- Conversión a filas de texto ------------------------------------

  @doc "Convierte un albergue en la fila que guarda `Storage`."
  @spec a_fila(Albergue.t()) :: [term()]
  def a_fila(albergue) do
    [
      albergue.codigo,
      albergue.nombre,
      albergue.zona,
      albergue.capacidad,
      albergue.ocupacion,
      albergue.personas |> Enum.sort() |> Enum.join(";"),
      Enum.join(albergue.recursos, ";"),
      Enum.join(albergue.necesidades, ";")
    ]
  end

  @doc "Reconstruye un albergue desde su fila. Una fila dañada devuelve `:error`."
  @spec desde_fila([String.t()]) :: {:ok, Albergue.t()} | :error
  def desde_fila([codigo, nombre, zona, capacidad, ocupacion, personas, recursos, necesidades]) do
    personas = personas |> String.split(";", trim: true) |> MapSet.new()

    with {c, ""} when c >= 0 <- Integer.parse(capacidad),
         {o, ""} when o >= 0 and o <= c <- Integer.parse(ocupacion),
         true <- o >= MapSet.size(personas) do
      {:ok,
       %Albergue{
         codigo: codigo,
         nombre: nombre,
         zona: zona,
         capacidad: c,
         ocupacion: o,
         personas: personas,
         recursos: String.split(recursos, ";", trim: true),
         necesidades: String.split(necesidades, ";", trim: true)
       }}
    else
      _ -> :error
    end
  end

  def desde_fila(_otra), do: :error

  # --- Validaciones ---------------------------------------------------

  defp normalizar_codigo(codigo) when is_binary(codigo) do
    case String.trim(codigo) do
      "" -> {:error, :datos_invalidos}
      limpio -> {:ok, String.upcase(limpio)}
    end
  end

  defp normalizar_codigo(_otro), do: {:error, :datos_invalidos}

  defp validar_texto(texto) do
    if is_binary(texto) and String.trim(texto) != "", do: :ok, else: {:error, :datos_invalidos}
  end

  # El documento se guarda tal cual; se rechaza ";" porque separa los documentos en el archivo.
  defp validar_documento(documento) when is_binary(documento) or is_integer(documento) do
    limpio = documento |> to_string() |> String.trim()

    if limpio == "" or String.contains?(limpio, ";"),
      do: {:error, :documento_invalido},
      else: {:ok, limpio}
  end

  defp validar_documento(_otro), do: {:error, :documento_invalido}

  defp validar_capacidad(capacidad) when is_integer(capacidad) and capacidad >= 0, do: :ok
  defp validar_capacidad(_capacidad), do: {:error, :capacidad_invalida}

  defp validar_ocupacion(ocupacion, capacidad)
       when is_integer(ocupacion) and ocupacion >= 0 and ocupacion <= capacidad,
       do: :ok

  defp validar_ocupacion(_ocupacion, _capacidad), do: {:error, :ocupacion_invalida}

  defp validar_libre(mapa, codigo) do
    if Map.has_key?(mapa, codigo), do: {:error, :codigo_duplicado}, else: :ok
  end

  defp minusculas(texto), do: texto |> to_string() |> String.trim() |> String.downcase()
end
