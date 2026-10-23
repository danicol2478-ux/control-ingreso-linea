# Guía: Ingreso En Línea (Google Sheets + app nueva)

Esta es una **app distinta** a *Control Ingreso*. Se instala **al lado** de la otra:
las dos pueden estar en el mismo celular sin molestarse.

```
 📱 Celular 1 (Puerta A) ──┐
                           ├──► 📊 Google Sheets ◄── 💻 tú ves el Excel en vivo
 📱 Celular 2 (Puerta B) ──┘     (una sola lista para todos)
```

| | Control Ingreso (la vieja) | Ingreso En Línea (la nueva) |
|---|---|---|
| Lista de invitados | Excel guardado en el celular | Google Sheets en internet |
| Varios celulares | Cada uno con su lista | Todos con la MISMA lista |
| Necesita internet | No | Sí |
| Ver resultados | Compartir el Excel | Abrir la hoja: se actualiza sola |

Hay 4 partes. Hazlas en orden.

---

## PARTE 1: Crear la hoja en Google Sheets (en el PC)

1. Entra a **drive.google.com** con tu correo de Gmail.
2. Arriba a la izquierda toca **＋ Nuevo** → **Subir archivo** → elige
   **plantilla_invitados_en_linea.xlsx**.
3. Cuando suba, haz **doble clic** sobre el archivo. Se abre en Google Sheets.
4. Arriba toca **Archivo** → **Guardar como Hojas de cálculo de Google**.
   Se abre una pestaña nueva: **esa** es la hoja con la que vas a trabajar.
5. Abajo a la izquierda, la pestaña debe llamarse **Invitados**.
   (Si se llama distinto: clic derecho → Cambiar nombre → `Invitados`).

**Columnas:** la única obligatoria es **Cedula**. Puedes agregar las que quieras
(Empresa, Cargo, Mesa...). Las columnas *Estado, Hora_confirmacion, Hora_ingreso,
Puerta* las llena la app sola.

---

## PARTE 2: Pegar el programa en la hoja (en el PC)

1. En la hoja, arriba toca **Extensiones** → **Apps Script**.
2. Se abre un editor con un código que dice `function myFunction() { }`.
   **Borra todo** (Ctrl + E, luego Supr).
3. Abre el archivo **google/Codigo.gs** (con el Bloc de notas), copia todo
   (Ctrl + E, Ctrl + C) y pégalo en el editor (Ctrl + V).
4. Arriba, en la línea `const CLAVE = 'evento2026';` puedes cambiar
   `evento2026` por tu propia clave. **Anótala**: la vas a escribir en el celular.
5. Toca el ícono de **guardar 💾** (o Ctrl + S).

---

## PARTE 3: Publicar la hoja como "aplicación web" (en el PC)

1. Arriba a la derecha toca el botón azul **Implementar** → **Nueva implementación**.
2. Al lado de *Seleccionar tipo* toca el engranaje ⚙️ → **Aplicación web**.
3. Llena así:
   - **Descripción:** `Ingreso evento`
   - **Ejecutar como:** **Yo** (tu correo)
   - **Quién tiene acceso:** **Cualquier persona**
4. Toca **Implementar**.
5. Google pide permiso: toca **Autorizar acceso** → elige tu correo.
   Sale *"Google no verificó esta app"*: toca **Configuración avanzada** →
   **Ir a ... (no seguro)** → **Permitir**.
   (Es normal: la "app" es tu propio programa, Google solo avisa porque no lo revisó.)
6. Aparece la **URL de la aplicación web**, termina en `/exec`. Toca **Copiar**.
7. Mándatela por **WhatsApp** a tu chat (Tú). La vas a pegar en el celular.

> 🔒 La dirección + la clave son la "llave" de tu lista. No las publiques.

---

## PARTE 4: Fabricar e instalar la app nueva

Igual que la primera vez, pero en un **repositorio nuevo**:

1. En GitHub: **＋** → **New repository** → nombre `control-ingreso-linea` → **Create**.
2. **uploading an existing file** → arrastra la carpeta **lib** y **pubspec.yaml**
   → **Commit changes**.
3. **Add file** → **Create new file** → nombre `.github/workflows/construir-apk.yml`
   → pega el contenido de ese archivo → **Commit changes**.
4. **Actions** → espera el ✅ → **Artifacts** → descarga **ingreso-en-linea-apk**.
5. Mándate **app-release.apk** por WhatsApp e instálalo.
   **No hay que desinstalar la vieja**: esta es otra app.

---

## Usar la app

1. La primera vez se abre **Conectar con la hoja**:
   - **Dirección de la hoja:** pega la URL que te mandaste por WhatsApp.
   - **Clave:** la de la PARTE 2 (`evento2026` si no la cambiaste).
   - **Nombre de esta puerta:** por ejemplo `Puerta principal`.
2. Toca **Probar conexión** → debe decir ✅ *Conectado. La hoja tiene 20 invitados.*
3. Toca **Guardar**.
4. Escanea igual que en la otra app: **1. Confirmar** y **2. Ingreso**.
5. En el PC, deja abierta la hoja de Google Sheets: verás aparecer el estado,
   la hora y la puerta de cada persona **en vivo**.

Para otro evento o empresa: borra las filas de la hoja y pega la nueva lista
(con la columna **Cedula**). **No hay que cambiar nada en la app.**

## Si algo falla

| Mensaje en la app | Qué hacer |
|---|---|
| Clave incorrecta | La clave del celular no es igual a la de `const CLAVE` |
| La dirección no es la de la aplicación web | Copia otra vez la URL que termina en `/exec` |
| Sin conexión / Sin respuesta | Revisa los datos o el WiFi del celular |
| No se encontró una columna llamada "Cedula" | Revisa el encabezado de la hoja |
| Cambié el programa y no se nota | Implementar → Gestionar implementaciones → ✏️ → Versión: **Nueva versión** → Implementar |
