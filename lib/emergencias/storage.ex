defmodule Emergencias.Storage do
  @moduledoc """
  Persistencia genérica en archivos de texto plano.

  Cada registro es una línea con campos separados por `|`
  (`campo|campo|campo`). Los caracteres especiales se escapan:

    * `\\` se guarda como `\\\\`
    * `|`  se guarda como `\\|`
    * salto de línea se guarda como `\\n`

  El directorio se configura con
  `Application.put_env(:emergencias, :data_dir, "ruta")` y por defecto
  es `data/`. Los archivos son `nombre` relativos a ese directorio,
  por ejemplo `"recursos.txt"`.

  Devuelve `:ok` / `{:ok, filas}` / `{:error, razon}`; nunca lanza
  excepciones por situaciones esperadas.
  """

  alias Emergencias.Resultado

  @type fila :: [String.t()]

  @doc "Directorio donde se guardan los archivos."
  @spec directorio() :: String.t()
  def directorio do
    Application.get_env(:emergencias, :data_dir, "data")
  end

  @doc "Ruta completa de un archivo de datos."
  @spec ruta(String.t()) :: String.t()
  def ruta(nombre), do: Path.join(directorio(), nombre)

  @doc """
  Agrega un registro al final del archivo.

  Cada campo se convierte con `to_string/1`. Una sola escritura en modo
  `:append` por registro, así que varios procesos pueden agregar a la
  vez sin mezclar líneas.
  """
  @spec agregar(String.t(), [term()]) :: :ok | {:error, term()}
  def agregar(nombre, campos) when is_binary(nombre) and is_list(campos) do
    with :ok <- File.mkdir_p(directorio()) do
      File.write(ruta(nombre), codificar_linea(campos) <> "\n", [:append])
    end
  end

  @doc """
  Lee todos los registros. Un archivo que aún no existe es una lista vacía.
  """
  @spec leer(String.t()) :: Resultado.t([fila()])
  def leer(nombre) when is_binary(nombre) do
    case File.read(ruta(nombre)) do
      {:ok, contenido} ->
        filas =
          contenido
          |> String.split("\n", trim: true)
          |> Enum.map(&decodificar_linea/1)

        {:ok, filas}

      {:error, :enoent} ->
        {:ok, []}

      {:error, razon} ->
        {:error, razon}
    end
  end

  @doc """
  Reemplaza todo el contenido del archivo con las filas dadas.

  Escribe primero a un archivo temporal y luego lo renombra, así un
  fallo a la mitad no deja el archivo original truncado.
  """
  @spec reescribir(String.t(), [[term()]]) :: :ok | {:error, term()}
  def reescribir(nombre, filas) when is_binary(nombre) and is_list(filas) do
    destino = ruta(nombre)
    temporal = destino <> ".tmp"

    contenido =
      filas
      |> Enum.map(fn campos -> codificar_linea(campos) <> "\n" end)
      |> IO.iodata_to_binary()

    with :ok <- File.mkdir_p(directorio()),
         :ok <- File.write(temporal, contenido) do
      File.rename(temporal, destino)
    end
  end

  # --- Codificación -------------------------------------------------

  @doc "Convierte una lista de campos en una línea de texto (sin salto final)."
  @spec codificar_linea([term()]) :: String.t()
  def codificar_linea(campos) do
    campos
    |> Enum.map(&escapar/1)
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea de texto en la lista de campos original.

  Es recursiva sobre el binario: consume un fragmento por vez y
  acumula el campo actual y los campos ya terminados.
  """
  @spec decodificar_linea(String.t()) :: fila()
  def decodificar_linea(linea), do: decodificar(linea, "", [])

  defp escapar(campo) do
    campo
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\|")
    |> String.replace("\n", "\\n")
  end

  # Fin de la línea: el campo en curso es el último.
  defp decodificar(<<>>, actual, acumulados), do: Enum.reverse([actual | acumulados])

  defp decodificar(<<"\\\\", resto::binary>>, actual, acumulados),
    do: decodificar(resto, actual <> "\\", acumulados)

  defp decodificar(<<"\\|", resto::binary>>, actual, acumulados),
    do: decodificar(resto, actual <> "|", acumulados)

  defp decodificar(<<"\\n", resto::binary>>, actual, acumulados),
    do: decodificar(resto, actual <> "\n", acumulados)

  # Un `|` sin escapar cierra el campo actual.
  defp decodificar(<<"|", resto::binary>>, actual, acumulados),
    do: decodificar(resto, "", [actual | acumulados])

  defp decodificar(<<byte, resto::binary>>, actual, acumulados),
    do: decodificar(resto, <<actual::binary, byte>>, acumulados)
end
