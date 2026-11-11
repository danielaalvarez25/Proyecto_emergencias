# Comandos de la Persona A: qué función llamar

Guía para el parser del CLI (Persona B). Todas las funciones devuelven
`{:ok, valor}` o `{:error, razon}`; el CLI debe traducir la razón a un mensaje.

## Reglas para el parser

- **Convertir los números antes de llamar.** El dominio rechaza texto: `"30"` da
  `{:error, :cantidad_invalida}`. Usar `Integer.parse/1` y, si no es un entero
  limpio, responder error de formato sin llamar al dominio.
- **Los procesos ya están arrancados** por `Emergencias.Application`; no hay que
  crear nada.
- **Los ids de necesidad son `N001`, `N002`...** (el enunciado muestra `need001`;
  el parser debe usar `N001` o traducir). Los códigos de albergue no distinguen
  mayúsculas (`a01` = `A01`).
- **Los filtros de `list_needs`** (`zona=centro prioridad=critica`) se pasan como
  keyword: `zona: "centro", prioridad: "critica"`. Los valores pueden ir como
  texto; ignoran mayúsculas y tildes.
- **Permisos y bitácora** los resuelve B antes de llamar (según el tipo de usuario).

## Tabla de comandos

| Comando | Función | Notas |
|---|---|---|
| `register_resource R001 agua 200 litros centro_acopio_1` | `Recursos.registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion)` | El comando no trae categoría: pasar `""` (texto vacío). Cantidad entera >= 0. |
| `list_resources` | `Recursos.listar()` | Devuelve `{:ok, [%Recurso{}]}`. Filtros opcionales: `nombre:`, `ubicacion:`, `categoria:`. |
| `transfer_resource R001 centro_acopio_1 albergue_2 30` | `Recursos.transferir(codigo, origen, destino, cantidad)` | El origen debe ser la ubicación actual del recurso. |
| `critical_resources` | `Recursos.criticos(umbral)` | Recursos con cantidad menor o igual al umbral (por defecto 20), los más escasos primero. |
| `register_need agua 30 critica centro "Punto de atención sector 3"` | `Necesidades.registrar(tipo, cantidad, prioridad, zona, descripcion, responsable)` | `responsable` = usuario conectado. Devuelve la necesidad con su id. |
| `list_needs` / `list_needs zona=centro prioridad=critica` | `Necesidades.listar(filtros)` | Filtros: `zona`, `tipo`, `prioridad`, `estado`. Sale ordenado por prioridad. |
| `pending_needs` | `Necesidades.pendientes()` | De la más urgente a la menos urgente. |
| `assign_resource N001 agua 30` | `Despacho.asignar(id, recurso, cantidad)` | Corre en un proceso supervisado. Equivale a `Necesidades.asignar/3`. |
| `register_shelter A01 "Albergue Norte" zona_norte 150` | `Albergues.registrar(codigo, nombre, zona, capacidad)` | Quinto argumento opcional: ocupación inicial. |
| `check_shelter A01` | `Albergues.consultar(codigo)` y luego `Cupos.resumen/1` | El resumen trae capacidad, ocupación, cupos y porcentaje. |
| `register_entry A01 documento` | `Albergues.ingresar(codigo, documento)` | B debe además pasar la persona a estado `en_albergue`. |
| `register_exit A01 documento` | `Albergues.salir(codigo, documento)` | |

### Para `summary`

| Dato | Función |
|---|---|
| Recursos restantes | `Recursos.listar()` |
| Necesidades (pendientes, por estado) | `Necesidades.listar(estado: "pendiente")` y similares |
| Albergues y ocupación | `Albergues.listar()` y `Albergues.reporte_ocupacion(3)` |

### Funciones extra disponibles

| Función | Para qué sirve |
|---|---|
| `Necesidades.cambiar_estado(id, estado)` | Pasar a `en_atencion`, `atendida` o `cancelada`. |
| `Necesidades.atender_por_prioridad()` | Atiende las pendientes de la más urgente a la menos urgente con el inventario disponible. |
| `Despacho.asignar_varias([{id, recurso, cantidad}])` | Demo del conflicto concurrente (todas a la vez, un proceso por pedido). |
| `Recursos.entrada/3`, `Recursos.salida/3`, `Recursos.historial/1` | Entradas, salidas e historial de movimientos. |
| `Albergues.asociar_recurso/2`, `Albergues.asociar_necesidad/2` | Asociar al albergue (comprueba que existan). |
| `Albergues.donde_esta(documento)` | Albergue donde está una persona. |

## Razones de error para traducir a mensajes

| Razón | Aparece en | Significado |
|---|---|---|
| `:datos_invalidos` | recursos, necesidades, albergues | Campo vacío o de tipo incorrecto |
| `:cantidad_invalida` | recursos, necesidades | No es un entero válido (o es <= 0) |
| `:codigo_duplicado` | recursos, albergues | El código ya existe |
| `:no_existe` | todos | El código o id no existe |
| `:stock_insuficiente` | recursos, asignación | No alcanza el inventario |
| `:origen_incorrecto`, `:destino_invalido` | transferencias | Origen distinto a la ubicación del recurso, o destino igual al origen |
| `:tipo_invalido`, `:prioridad_invalida`, `:zona_invalida`, `:estado_invalido` | necesidades | Valor fuera de los permitidos |
| `:transicion_invalida` | necesidades | Cambio de estado no permitido |
| `:necesidad_cerrada` | necesidades | Ya está atendida o cancelada |
| `:ya_asignada` | necesidades | La necesidad ya está cubierta |
| `:excede_necesidad` | asignación | Se pidió más de lo que le falta a la necesidad |
| `:capacidad_invalida`, `:ocupacion_invalida` | albergues | Capacidad u ocupación inicial inválida |
| `:albergue_lleno` | albergues | Sin cupos |
| `:persona_ya_registrada`, `:persona_en_otro_albergue`, `:persona_no_registrada` | albergues | Problemas con la persona alojada |
| `:documento_invalido` | albergues | Documento vacío o con `;` |
| `:ya_asociado`, `:recurso_no_existe`, `:necesidad_no_existe` | albergues | Asociaciones |
| `:no_alojada` | albergues | La persona no está en ningún albergue |
| `:timeout`, `{:proceso_caido, razon}` | despacho | La asignación no respondió o su proceso cayó |
