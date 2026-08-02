-- ============================================================
--  Tablero de plazas de internado — esquema
--  Ejecutar en Supabase: SQL Editor -> pegar -> Run
-- ============================================================

-- Las sedes son fijas, pero en tabla para que las plazas no queden
-- escritas dentro del código: cambiar un cupo es un UPDATE.
-- Va primero porque estudiantes.sede_id la referencia.
create table if not exists public.sedes (
  id      text    primary key,
  nombre  text    not null,
  plazas  integer not null check (plazas >= 0),
  orden   integer not null default 0
);

-- Cada estudiante lleva su sede en una columna.
-- Asignar = actualizar una celda. Liberar = ponerla en NULL.
create table if not exists public.estudiantes (
  id           integer      primary key,
  apellidos    text         not null,
  nombres      text         not null,
  codigo       text,
  cedula       text,
  correo_inst  text,
  correo_pers  text,
  celular      text,
  gpa          numeric(6,2),   -- promedio; define el orden de prioridad
  creditos     numeric(8,2),
  examen       numeric(6,2),   -- examen de ciencias clínicas
  pensum       text,           -- pensum / malla
  discapacidad text,
  embarazada   text,
  hijos        integer,
  estado_civil text,
  sede_id      text         references public.sedes(id) on delete set null,
  actualizado  timestamptz  not null default now()
);

-- Si la tabla ya existía (versión anterior), agrega las columnas nuevas.
alter table public.estudiantes add column if not exists creditos     numeric(8,2);
alter table public.estudiantes add column if not exists examen       numeric(6,2);
alter table public.estudiantes add column if not exists pensum       text;
alter table public.estudiantes add column if not exists discapacidad text;
alter table public.estudiantes add column if not exists embarazada   text;
alter table public.estudiantes add column if not exists hijos        integer;
alter table public.estudiantes add column if not exists estado_civil text;
alter table public.estudiantes add column if not exists bloqueado    boolean not null default false;

insert into public.sedes (id, nombre, plazas, orden) values
  ('heom', 'Hospital Enrique Ortega Moreira', 30, 1),
  ('hng',  'Hospital Naval Guayaquil',        19, 2),
  ('hagp', 'Hospital Abel Gilbert Pontón',    15, 3)
on conflict (id) do update
  set nombre = excluded.nombre,
      plazas = excluded.plazas,
      orden  = excluded.orden;

-- ------------------------------------------------------------
--  Regla de negocio: nunca exceder las plazas de una sede.
--  Aunque hoy use el tablero una sola persona, esto evita que un
--  error de la app o un UPDATE manual dejen la tabla inconsistente.
-- ------------------------------------------------------------
create or replace function public.verificar_cupo()
returns trigger
language plpgsql
as $$
declare
  ocupadas integer;
  limite   integer;
begin
  if new.sede_id is null then
    return new;
  end if;

  -- Sin cambio de sede no hay nada que validar
  if tg_op = 'UPDATE' and old.sede_id is not distinct from new.sede_id then
    return new;
  end if;

  select plazas into limite from public.sedes where id = new.sede_id;
  if limite is null then
    raise exception 'La sede % no existe', new.sede_id;
  end if;

  select count(*) into ocupadas
    from public.estudiantes
   where sede_id = new.sede_id
     and id <> new.id;

  if ocupadas >= limite then
    raise exception 'La sede % ya no tiene plazas libres (%/%)', new.sede_id, ocupadas, limite;
  end if;

  new.actualizado := now();
  return new;
end;
$$;

drop trigger if exists trg_verificar_cupo on public.estudiantes;
create trigger trg_verificar_cupo
  before insert or update on public.estudiantes
  for each row execute function public.verificar_cupo();

-- ------------------------------------------------------------
--  Seguridad
--
--  La anon key viaja en el código de la página, así que sin RLS
--  cualquiera leería las cédulas. El acceso NO se abre a cualquier
--  autenticado, sino solo a los correos de una lista blanca.
--
--  >>> Añade abajo (insert) los correos de quienes podrán entrar. <<<
--      (Los correos quedan en tu base, no en el repositorio.)
--      Para autorizar a alguien más luego:
--        insert into public.acceso_autorizado (email) values ('otro@correo');
--      Para revocar:
--        delete from public.acceso_autorizado where email = 'otro@correo';
-- ------------------------------------------------------------

-- Lista blanca de correos autorizados.
create table if not exists public.acceso_autorizado (
  email text primary key
);

insert into public.acceso_autorizado (email) values
  ('CORREO_AUTORIZADO')       -- reemplaza / agrega tantos como necesites
on conflict (email) do nothing;

-- La lista no se expone por la API: RLS activo y sin políticas de lectura.
alter table public.acceso_autorizado enable row level security;

-- Decide si quien entra está en la lista. security definer: consulta la lista
-- aunque el llamante no pueda leerla; search_path fijo por seguridad.
create or replace function public.es_autorizado()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.acceso_autorizado
    where email = (auth.jwt() ->> 'email')
  );
$$;

alter table public.estudiantes enable row level security;
alter table public.sedes       enable row level security;

drop policy if exists "estudiantes_lectura"     on public.estudiantes;
drop policy if exists "estudiantes_actualizar"  on public.estudiantes;
drop policy if exists "sedes_lectura"           on public.sedes;

create policy "estudiantes_lectura" on public.estudiantes
  for select to authenticated using (public.es_autorizado());

create policy "estudiantes_actualizar" on public.estudiantes
  for update to authenticated
  using (public.es_autorizado())
  with check (public.es_autorizado());

-- La app solo cambia la sede y el bloqueo. RLS no puede filtrar por columna,
-- así que se limita el UPDATE a esas dos con privilegios de columna: un intento
-- de tocar cédula, nombres o correos desde la app recibe "permission denied".
-- El trigger corre como dueño de la tabla, así que puede seguir fijando
-- 'actualizado' sin que el llamante tenga ese privilegio.
revoke update on public.estudiantes from authenticated;
grant  update (sede_id, bloqueado) on public.estudiantes to authenticated;

create policy "sedes_lectura" on public.sedes
  for select to authenticated using (public.es_autorizado());
