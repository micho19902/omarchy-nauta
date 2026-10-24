# Nauta

Widget de la barra de Omarchy para el portal cautivo **Nauta** de ETECSA
(Cuba). Detecta cuándo la red te está pidiendo autenticarte, inicia sesión con
una cuenta guardada, muestra el tiempo restante y permite cerrar sesión.

## Qué hace

- Sondea la conexión cada 30 s (configurable) y distingue entre *en línea*,
  *portal Nauta* y *sin conexión*.
- Con el inicio automático activado, al detectar el portal entra solo con la
  cuenta marcada como predeterminada. Si no hay ninguna marcada, no entra
  solo: hace falta marcar una con la estrella.
- Consulta el tiempo restante en el propio portal y lo muestra en el panel
  (`1:05:09`), con cuenta atrás local entre consultas. En la barra se ve solo
  el icono; si quieres el tiempo al lado, activa la opción «Texto junto al
  icono» en los ajustes del widget.
- Guarda varias cuentas: usuario, etiqueta, cuenta predeterminada y contraseña
  en el **llavero del sistema** (secret-tool / gnome-keyring), nunca en texto
  plano.
- Cerrar sesión desde el panel (también libera el tiempo en el portal).

## Uso

| Acción | Qué hace |
| --- | --- |
| Clic izquierdo | Abre el panel |
| Clic derecho | Vuelve a comprobar conexión y cuentas |
| Clic central | Conecta con la cuenta predeterminada, o cierra sesión si ya estás dentro |

En el panel: el interruptor del encabezado activa/desactiva el inicio
automático; la estrella marca o desmarca la cuenta predeterminada (volver a
pulsarla la desmarca); el lápiz abre la cuenta en el formulario para cambiar
usuario, etiqueta o contraseña (si dejas la contraseña vacía se mantiene la
actual); la papelera pide confirmación antes de borrar una cuenta.

## Archivos

```
~/.config/omarchy/plugins/mich.nauta/
├── Panel.qml          # icono de la barra + panel
├── Service.qml        # estado, cola de trabajos y auto-login
├── Model.js           # formato de textos y validaciones
├── manifest.json
└── bin/nauta          # cliente del portal (Python, solo stdlib)
```

Datos en `~/.config/omarchy/nauta/`:

- `accounts.json` (0600): usuarios y etiquetas. **Sin contraseñas.**
- `state.json` (0600): sesión activa del portal (`ATTRIBUTE_UUID`, `CSRFHW`,
  `wlanuserip`, token de tiempo). Se borra al cerrar sesión.
- Contraseñas: `secret-tool` con `service=nauta username=<usuario>`.

## Protocolo

1. `GET https://secure.etecsa.net:8443/` y se leen los campos ocultos del
   formulario `#formulario` (`CSRFHW`, `wlanuserip`, `loggerId`, …).
2. `POST` al `action` del formulario con usuario y contraseña. La respuesta
   trae `ATTRIBUTE_UUID=…` y, en la página de sesión, la URL con la que el
   propio portal consulta el tiempo (`op=getLeftTime&op1=…&op2=…`).
3. Ese token se guarda y se usa para `POST /EtecsaQueryServlet`, que responde
   `HH:MM:SS`. Si el portal responde `errorop`, la sesión caducó y se descarta.
4. `GET /LogoutServlet?CSRFHW=…&ATTRIBUTE_UUID=…&username=…&wlanuserip=…`.

La verificación TLS va desactivada, igual que en el resto de clientes Nauta:
el portal usa un certificado que no está en los almacenes públicos. Es un
compromiso consciente, no un descuido.

## Problemas

- **"Sin conexión" pero la WiFi está bien**: el sondeo usa
  `http://nmcheck.gnome.org/check_network_status.txt`; si la red bloquea ese
  dominio, el estado queda en `offline` aunque haya internet.
- **"Sesión no gestionada por el plugin"**: ya estabas conectado desde el
  navegador. Cierra esa sesión en el portal y deja que el plugin entre, o sigue
  así (el tiempo restante solo se puede leer con la sesión que abrió el
  plugin).
- **No hay contraseña guardada**: vuelve a añadir la cuenta para escribirla de
  nuevo; se guarda en el llavero, no en `accounts.json`.
- **El icono no aparece**: `omarchy-shell shell rescanPlugins`, luego
  `omarchy plugin enable mich.nauta` y colócalo con `omarchy bar move
  mich.nauta --section right`.

Para depurar el cliente a mano:

```bash
~/.config/omarchy/plugins/mich.nauta/bin/nauta status | python3 -m json.tool
~/.config/omarchy/plugins/mich.nauta/bin/nauta accounts | python3 -m json.tool
```
