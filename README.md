# Tablero de Plazas de Internado

Asignación drag & drop de postulantes a sedes hospitalarias, con exportación a Excel
por sede y consolidada. La página es un único HTML autónomo: sin backend, sin build
de framework, sin dependencias en tiempo de ejecución.

La nómina se ordena por **GPA descendente**: el postulante con mayor promedio elige
plaza primero (es la prioridad de selección). El GPA se muestra en cada ficha y va
como columna en los Excel. Incluye **tema claro/oscuro** con botón en la barra, que
respeta la preferencia del sistema y recuerda la elección.

| Sede | Plazas |
|---|---|
| Hospital Enrique Ortega Moreira | 30 |
| Hospital Naval Guayaquil | 19 |
| Hospital Abel Gilbert Pontón | 15 |
| **Total** | **64** |

## Estructura

```
data/estudiantes.json   los 64 postulantes (NO se versiona: datos personales)
src/plantilla.html      la app: estilos, marcado y lógica, con marcador de datos
scripts/build.js        inyecta los datos y genera cada variante
docs/index.html         build PÚBLICO  -> lo que sirve GitHub Pages
dist/                   builds INTERNOS -> nunca se versiona
```

## Builds

```bash
node scripts/build.js publico    # docs/index.html    cédula y celular enmascarados
node scripts/build.js interno    # dist/index.html    datos completos
node scripts/build.js artifact   # dist/artifact.html sin <html>/<head>/<body>
```

Una sola plantilla alimenta las tres variantes, así que un cambio en la interfaz
llega a todas sin copiar código.

## Publicar con acceso restringido (Supabase + GitHub Pages)

Como solo una persona entra, los datos van completos detrás del login. Para que
eso sea real, **el sitio publicado no lleva ningún dato en el código**: se cargan
desde la tabla tras iniciar sesión. Por eso `node scripts/build.js publico`
**se niega a construir** si no hay tabla configurada — así es imposible publicar
sin querer un HTML con las 64 cédulas dentro.

1. Crea un proyecto en [supabase.com](https://supabase.com) (plan gratuito).
   Elige la región más cercana (**South America / São Paulo**) y guarda la
   contraseña de la base — es distinta de la del acceso a la app.
2. Abre `supabase/01-esquema.sql`, reemplaza **todas** las apariciones de
   `CORREO_AUTORIZADO` por el correo de la única persona que entrará (usa
   Buscar y reemplazar), y ejecútalo en **SQL Editor**.
3. Genera la carga de datos y ejecútala igual en SQL Editor:
   ```bash
   node scripts/seed.js      # crea supabase/02-datos.sql (con datos reales; no se versiona)
   ```
4. **Authentication → Users → Add user**: crea ese único usuario con su correo y
   contraseña, y **marca "Auto Confirm User"** (si no, el login da "email not
   confirmed"). *(La contraseña no se guarda en ningún archivo: la pide la
   pantalla de acceso en cada sesión.)*
5. **Authentication → Sign In / Providers → Email**: **desactiva "Allow new users
   to sign up"**. Así nadie puede auto-registrarse; solo existirá el usuario que
   creaste.
6. **Settings → API**: copia `Project URL` y la clave `anon public` en
   `src/config.json` (la `service_role` NO, esa es secreta).
7. Construye y publica:
   ```bash
   node scripts/build.js publico     # ahora sí: docs/index.html sin datos, con login
   git add -A && git commit -m "Conecta la tabla" && git push
   ```
   En GitHub: **Settings → Pages → Deploy from a branch**, rama `main`, carpeta `/docs`.

La `anon key` sí puede ser pública: sola no lee nada. Solo el correo autorizado,
tras iniciar sesión, puede leer y mover plazas.

### Quién puede entrar

El acceso está cerrado en **tres capas**, no en una:

1. La policy RLS solo deja leer/escribir al correo autorizado (`CORREO_AUTORIZADO`).
2. Los registros públicos desactivados: nadie más puede crearse una cuenta.
3. Existe un solo usuario en Authentication.

### Cómo queda repartido

| Dónde | Qué contiene |
|---|---|
| Tabla `estudiantes` | Los 64 registros completos, con su `sede_id` |
| Tabla `sedes` | Los cupos (30 / 19 / 15) — cambiarlos es un UPDATE |
| HTML publicado | Ningún dato personal: llegan tras iniciar sesión |
| Contraseña | En ningún archivo; solo en el gestor de quien entra |

La app solo puede cambiar la sede de un estudiante: un privilegio de columna en la
base impide que toque cédula, nombres o correos aunque se lo pidan. Un trigger
impide superar los cupos; si la base rechaza un cambio, la pantalla lo revierte en
lugar de mostrar algo que no se guardó. Al cerrar sesión, los datos se borran de la
memoria y de la pantalla.

### Descargas

Funcionan igual con login: el Excel se arma en el navegador con los datos completos
que se cargaron de la tabla (cédulas y celulares sin enmascarar). Cada botón deja
además un enlace de respaldo por si el navegador bloquea la descarga automática.

## Protección de datos

GitHub Pages gratuito exige repositorio público, y en un sitio estático todo lo que
la página muestra viaja en el código fuente. Por eso los datos reales **nunca entran
al repositorio**:

- `data/estudiantes.json`, `supabase/02-datos.sql` y `dist/` están en `.gitignore`.
  En el repo solo queda `data/estudiantes.ejemplo.json` (inventado).
- `node scripts/build.js publico` **se niega a construir** sin Supabase configurado,
  y aun configurado **aborta** si detecta cualquier dato personal en el HTML.
- El HTML publicado no lleva datos: se cargan de la tabla tras iniciar sesión.

Los modos `interno` y `artifact` sí incrustan los datos completos, pero escriben a
`dist/` (ignorado): son para uso local, Docker o el artifact privado — **no se
publican**.

## Docker (uso interno, datos completos)

Proyecto aislado: nombre, red y puerto propios, no interfiere con otros contenedores.

```bash
docker compose up -d --build
```

Disponible en **http://localhost:8093**. Sirve el build interno con nginx, sin caché
y con `robots.txt` bloqueando indexación.

```bash
docker compose down
```

## Publicar en GitHub Pages

```bash
git remote add origin https://github.com/USUARIO/plazas-internado.git
git branch -M main
git push -u origin main
```

Luego en **Settings → Pages**: Source `Deploy from a branch`, Branch `main`, carpeta
`/docs`. La URL queda como `https://USUARIO.github.io/plazas-internado`.

El HTML público incluye `<meta name="robots" content="noindex, nofollow">` para
mantenerlo fuera de los buscadores.

## Descargas de Excel

El Excel se arma en el navegador (un `.xlsx` es un ZIP de XML; el ZIP se construye a
mano con CRC32 propio, sin librerías).

Al pulsar descargar se intenta el clic programático y **además** aparece un enlace de
respaldo. Esto es deliberado: si la página está embebida en un iframe con sandbox, el
navegador ignora el clic programático sin lanzar error y sin dejar rastro detectable
desde JavaScript. El enlace de respaldo, pulsado por una persona, sí funciona.
