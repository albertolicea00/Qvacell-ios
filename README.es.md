# 🇨🇺 Qvacell

> Tu cell en Cuba. Cambiamos la letra, mantenemos el sonido.

[![Plataforma](https://img.shields.io/badge/plataforma-iOS%2017.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-15.0%2B-blue.svg)](https://developer.apple.com/xcode/)
![PRs Bienvenidos](https://img.shields.io/badge/PRs-bienvenidos-brightgreen)
[![Sincronización Android](https://github.com/albertolicea00/Qvacell-ios/actions/workflows/cross-platform-sync-check.yml/badge.svg)](https://github.com/albertolicea00/Qvacell-ios/actions/workflows/cross-platform-sync-check.yml)

Una aplicación para iPhone para acceder rápidamente a los **códigos de servicio USSD de ETECSA (Cubacel)**: consulta tu saldo, compra paquetes de datos/voz/SMS, transfiere saldo y más — todo desde una lista limpia y organizada que envía el código directamente al marcador del sistema.

[Read English version](README.md)

## ⚠️ Descargo de Responsabilidad

> [!WARNING]
> Esta es una aplicación independiente hecha por la comunidad. **No está afiliada, respaldada ni patrocinada por ETECSA**.  
> Los códigos pueden cambiar en cualquier momento a discreción del operador.

## ✨ Características

- 📋 **Catálogo USSD Completo** — Organizado por categorías (Saldo y Planes, Compras, Transferencias, Utilidades) con solicitudes interactivas según entradas necesarias.
- 📞 **Marcado en Un Tap** — Ejecución instantánea abriendo el marcador nativo del sistema con `#` codificado correctamente.
- 👤 **Integración con Contactos** — Accede a la agenda del dispositivo para llamar, transferir saldo o realizar llamadas a cobro revertido `*99` directamente.
- 🆔 **Extensión Identificador de Llamadas** — Extensión CallKit que etiqueta las llamadas a cobro revertido `*99` entrantes con el nombre real del contacto.
- 🛜 **Directorio de Salas de Navegación y Wi-Fi** — Búsqueda offline de salas de navegación de ETECSA y puntos Wi-Fi públicos por provincia.
- ✉️ **Catálogo de Servicios SMS** — Examina y prellena consultas de servicios por SMS (noticias, tiempo, deportes, tarifas de servicios) sin envío silencioso.
- 📶 **Prueba de Velocidad de Internet** — Medidor de prueba de velocidad de ping, descarga y subida integrado con endpoints de Cloudflare.
- 👥 **Gestión de Cuentas y PIN** — Almacena el PIN de transferencia en Keychain y gestiona números del Plan Amigo fácilmente.
- 🔔 **Recordatorios Locales** — Programa alertas recurrentes para compras de planes, recargas de saldo o transferencias con marcado en 1 toque.
- 🎙️ **Siri y Atajos de Voz** — Ejecuta consultas de saldo, códigos rápidos y llamadas a cobro revertido (`*99` / 99) o anónimas (`#31#` / oculto / privado) mediante comandos de voz nativos usando `AppIntents`.
- 🌗 **Personalización y Ajustes** — Soporte para tema Claro/Oscuro, selector de color de acento personalizado y pestaña de inicio configurable.

### Próximamente
- **Búsqueda en Directorio Online (Buscar en Directorio)** — Integración backend con web scraper para buscar en el directorio telefónico y comercial de ETECSA por categoría, número, municipio y provincia. Consulta [#3](https://github.com/albertolicea00/Qvacell-ios/issues/3) para más detalles.

## 🛠️ Requisitos

- 🍏 Xcode 15+
- 📱 iOS 17.0+
- ⚙️ [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## 🚀 Primeros Pasos

```bash
git clone https://github.com/albertolicea00/Qvacell-ios.git
cd Qvacell-ios
xcodegen generate
open Qvacell.xcodeproj
```

> **Nota sobre XcodeGen:** Este proyecto usa **XcodeGen** con una especificación `project.yml` para generar `Qvacell.xcodeproj` dinámicamente y evitar conflictos de fusión en `.pbxproj`.

Compila y ejecuta en un dispositivo. **El marcado USSD requiere un iPhone físico con una SIM de Cubacel** 📲 — el simulador no puede realizar llamadas.

Para activar el Identificador de Llamadas para llamadas `*99`, tras instalar la app ve a **Ajustes › Teléfono › Bloqueo e Identificación de Llamadas** en el dispositivo y activa **CallerID**. Este es un ajuste manual de iOS que se realiza una sola vez — ninguna app puede activarlo automáticamente. Consulta [ARCHITECTURE.md § 11](ARCHITECTURE.md#11-caller-id-extension-99-collect-call-identification) para entender los motivos.

## 🗂️ Estructura del Proyecto

```
Qvacell/
├── QvacellApp.swift  # Punto de entrada de la app
├── Models.swift              # USSDCode, USSDCategory, decodificación del catálogo, paleta de colores, Reminder/ReminderTemplate
├── Services.swift            # Almacén del catálogo JSON, Contactos, puente con marcador del sistema, ReminderManager (notificaciones locales)
├── UIComponents.swift        # Vistas de presentación reutilizables (fila de código)
├── Views.swift               # Pantallas de Inicio, Contactos, categorías y ajustes
├── codes.json                # Catálogo de códigos USSD incluido
└── wifi_navigation_rooms.json  # Directorio de salas de navegación/puntos Wi-Fi de ETECSA incluido

CallerIDExtension/             # Extensión CallKit Call Directory (etiqueta llamadas a cobro revertido *99)
└── CallDirectoryHandler.swift

Shared/                        # Código compartido entre la app y CallerIDExtension
└── CallerIDStore.swift        # Lista de IDs de llamadas respaldada por App Group (lectura/escritura)
```

*El catálogo completo de códigos USSD se carga dinámicamente desde nuestro archivo de configuración JSON [`Qvacell/codes.json`](Qvacell/codes.json), manteniendo la app ligera y fácil de actualizar.* 📁

## ☎️ Marcado Directo vs. Confirmación

Los códigos de consulta gratuitos se marcan inmediatamente. Los códigos de compra de pago se detienen en el menú de confirmación de ETECSA por defecto; la opción **Acción Rápida sin Confirmación** permite variantes de código con autoconfirmación con una advertencia visible en la interfaz.

## 🔍 Directorio Telefónico y Base de Datos Offline

En **Ajustes › Utilidades**:
- **Buscar en Directorio**: Búsqueda en el directorio telefónico y comercial (en construcción).
- **Buscar en Database**: Búsqueda inversa offline sobre una base de datos SQLite (`.db`) suministrada por el usuario. Por seguridad y privacidad, esta función viene oculta por defecto (se desbloquea tocando 5 veces la versión en *Acerca de*) y la búsqueda es estrictamente solo por número (sin búsqueda por nombre).

## 🛜 Salas de Navegación y Wi-Fi Público

Incluye un directorio offline de salas de navegación oficiales de ETECSA y puntos Wi-Fi públicos por provincia (el workflow [`wifi-rooms-sync-check`](.github/workflows/wifi-rooms-sync-check.yml) supervisa desvíos en los datos de origen).

## 🔄 Sincronización entre Plataformas

[`cross-platform-sync-check.yml`](.github/workflows/cross-platform-sync-check.yml) se ejecuta en cada push a `main` que modifique `codes.json` o `wifi_navigation_rooms.json`, y compara la copia de este repo contra la de [qvacell-apk](https://github.com/albertolicea00/Qvacell-apk) (la app Android). Si han divergido, abre (o actualiza) un issue en el *otro* repositorio para que se actualice la plataforma que quedó atrás. Solo se compara la **estructura** en `codes.json` (ids, cadenas de marcado, tipo de acción, manejo de entrada, ubicación en categoría/grupo) — los campos cosméticos (icono, precio, redacción del título, etc.) pueden diferir entre plataformas. Ver [ARCHITECTURE.md § 14](ARCHITECTURE.md#14-cross-platform-catalog-sync-check) para el detalle exacto de qué se compara y cómo.

## 🚧 Limitaciones Conocidas

- **La base de datos offline no está integrada con el ID de Llamadas (`*99`).** La base de datos importada por el usuario (`Buscar en Database`) se mantiene separada intencionalmente de `CallerIDStore`/`CallDirectoryHandler` (ver [ARCHITECTURE.md § 11](ARCHITECTURE.md#11-caller-id-extension-99-collect-call-identification)), el cual solo se carga desde los Contactos propios del dispositivo. Una extensión CallKit Call Directory tiene un límite estricto en la cantidad de entradas de identificación que puede registrar (alrededor de 100k–200k) — los volcados de base de datos tienen millones de filas (v1: ~4.6M; v2: ~4.8M combinados), por lo que registrarlos por completo provocaría el rechazo o desactivación de la extensión por parte de iOS.

- **Sin opción de "llamar por WhatsApp/Teams" en Contactos.** La pestaña Contactos solo ofrece acciones celulares (llamada normal, `*99` a cobro revertido, `#31#` anónima) al lado de cada contacto — no puede añadir una opción de "llamar por WhatsApp" o "llamar por Teams". Esas apps realizan llamadas sobre su propia pila VoIP/Wi-Fi, no sobre la red celular, y no exponen APIs públicas o esquemas URL que una app externa pueda usar para desencadenar una llamada a través de ellas.

- **Sandbox de seguridad de iOS y limitaciones USSD (sin seguimiento de saldo en tiempo real).** A diferencia de Android (donde las apps pueden interceptar respuestas USSD en segundo plano), la seguridad sandbox de iOS impide que apps de terceros lean o analicen diálogos de respuesta USSD, encadenen sesiones automáticamente o ejecuten consultas USSD en segundo plano. Debido a esta limitación del sistema, la app no puede mostrar o actualizar automáticamente tu saldo o paquetes en tiempo real dentro de la interfaz; marcar un código (`tel://`) transfiere la ejecución a la aplicación Teléfono nativa donde el usuario ve la respuesta directamente.

- **Sin widget en la Pantalla de Inicio.** Considerado y deliberadamente no construido. Una extensión de WidgetKit no puede llamar a `UIApplication.shared.open`/`tel://` en absoluto (`APPLICATION_EXTENSION_API_ONLY` desactiva esa API en extensiones), por lo que un widget nunca puede marcar un código por sí mismo.

- **Dispositivos físicamente dual-SIM (dos tarjetas nano-SIM).** Los modelos de iPhone vendidos en China continental, Hong Kong y Macao admiten dos tarjetas nano-SIM físicas. Esta app no tiene interfaz de selección de línea ni forma de forzar el marcado a través de una SIM específica; iOS siempre usa la línea marcada como predeterminada en los ajustes del dispositivo.

- **Sin soporte para iPad / iPadOS para USSD.** Apple bloquea por completo la ejecución de códigos USSD en iPadOS debido a la ausencia de la app Teléfono.

- **Sin soporte para Apple Watch / watchOS para USSD.** De forma similar, watchOS no admite la ejecución de códigos USSD.

## 🤝 Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md). Por favor, sigue el [Código de Conducta](CODE_OF_CONDUCT.md).

> ⚠️ **Los Issues, descripciones de PR y mensajes de commit deben escribirse en inglés.**
> La interfaz de la app está intencionalmente en español (está dirigida a usuarios cubanos). Toda la comunicación técnica sigue las convenciones en inglés.

## 📚 Fuentes
Los códigos se compilaron a partir de los siguientes sitios:
- https://galixpay.com/recargas-a-cuba/
- https://www.fonoma.com/blog/codigos-ussd-cuba
- https://www.etecsa.cu/es/taxonomy/term/1445
- https://www.etecsa.cu/en/rooms-public-spaces
- https://www.ecured.cu/Entumovil
- https://www.escambray.cu/2017/etecsa-informa-sobre-nuevos-servicios-de-telefonia-movil-para-clientes-prepago-infografia/
- https://www.entumovil.cu/#:~:text=Para%20activar%20las%20siguientes%20prestaciones%2C,portal%20el%20de%20su%20preferencia.

---

*Desarrollado por @albertolicea00*
