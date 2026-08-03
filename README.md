# Tablero de Plazas de Internado

Asignación drag & drop de postulantes a sedes hospitalarias, con exportación a Excel
por sede y consolidada. La página es un único HTML autónomo: sin backend, sin build
de framework, sin dependencias en tiempo de ejecución.

La nómina se ordena por **prioridad (Art. 11)** y, dentro de cada prioridad, por
**GPA**. Las prioridades se calculan solas: **P1** top 10% por GPA (mérito),
**P2** discapacidad/enfermedad, **P3** embarazo, **P4** hijos menores de 5, **P5**
soltero(a); el resto sin prioridad. Cada estudiante toma la mejor prioridad que le
aplique. La prioridad se ve en cada ficha (rail de color) y va como columna en los
Excel. Incluye **tema claro/oscuro** con botón en la barra, que respeta la
preferencia del sistema y recuerda la elección.

**Filtro avanzado (descalificar por criterios).** Además de la búsqueda por texto, el
botón *Filtros* abre un panel para descalificar candidatos por GPA, créditos, examen
de ciencias clínicas, pensum/malla, estado civil, hijos, discapacidad y embarazo. Se
combinan (todos deben cumplirse) y el tipo de control se detecta solo según los datos:
rango numérico para GPA/créditos/examen, chips de categoría (con etiquetas legibles)
para el resto. Los campos aparecen a medida que se llenan en el Excel.

**Bloqueo.** Quien tiene el examen de ciencias clínicas en 0 no aprobó el requisito:
sale en rojo, al final de la nómina y no se puede asignar. Excepción: quien viene de
una **malla anterior** (pensum distinto de 1360 y 1271) no rinde ese examen, así que
su 0 no lo bloquea — sale en **ámbar** ("no rinde examen"), movible y en su orden
normal. Además cada ficha tiene un botón para **bloquear/desbloquear** manualmente
(p. ej. documento faltante); el bloqueo se guarda en la base, así ambas coordinadoras
lo ven.

**Finalizar período.** El botón *Finalizar sorteo* cierra el tablero: nadie puede
asignar, mover, bloquear ni vaciar — solo descargar los reportes. El estado se guarda
en la base (`int_config`) y lo hacen cumplir también los endpoints (una escritura con
el período cerrado responde 423). *Reabrir período* lo revierte. Ambas acciones piden
confirmación.

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
2. Abre `supabase/01-esquema.sql`, en el `insert into public.acceso_autorizado`
   reemplaza `CORREO_AUTORIZADO` por el correo de quien podrá entrar (agrega más
   líneas si son varias personas), y ejecútalo en **SQL Editor**.
3. Genera la carga de datos y ejecútala igual en SQL Editor:
   ```bash
   node scripts/seed.js      # crea supabase/02-datos.sql (con datos reales; no se versiona)
   ```
4. **Authentication → Users → Add user**: crea a cada persona con su correo y
   contraseña, y **marca "Auto Confirm User"** (si no, el login da "email not
   confirmed"). *(La contraseña no se guarda en ningún archivo: la pide la
   pantalla de acceso en cada sesión.)* El correo debe coincidir con uno de la
   lista `acceso_autorizado`.
5. **Authentication → Sign In / Providers → Email**: **desactiva "Allow new users
   to sign up"**. Así nadie puede auto-registrarse; solo existirán los usuarios
   que crees.
6. **Settings → API**: copia `Project URL` y la clave `anon public` en
   `src/config.json` (la `service_role` NO, esa es secreta).
7. Construye y publica:
   ```bash
   node scripts/build.js publico     # ahora sí: docs/index.html sin datos, con login
   git add -A && git commit -m "Conecta la tabla" && git push
   ```
   En GitHub: **Settings → Pages → Deploy from a branch**, rama `main`, carpeta `/docs`.

La `anon key` sí puede ser pública: sola no lee nada. Solo los correos de la lista
`acceso_autorizado`, tras iniciar sesión, pueden leer y mover plazas.

### Quién puede entrar

El acceso está cerrado en **tres capas**, no en una:

1. La policy RLS (vía `es_autorizado()`) solo deja leer/escribir a los correos de
   la tabla `acceso_autorizado`. Todos con acceso idéntico.
2. Los registros públicos desactivados: nadie más puede crearse una cuenta.
3. Solo existen en Authentication los usuarios que creaste.

**Agregar o quitar una persona:** en **Table Editor → `acceso_autorizado`**,
inserta una fila con su correo (y créale usuario en Authentication) o bórrala para
revocar. No hace falta tocar código ni políticas.

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
