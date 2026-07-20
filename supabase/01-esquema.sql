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
  sede_id      text         references public.sedes(id) on delete set null,
  actualizado  timestamptz  not null default now()
);

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
--  cualquiera leería las cédulas. Además, si en Supabase quedan
--  activos los registros públicos, un desconocido podría auto-
--  registrarse y volverse "authenticated". Por eso el acceso NO
--  se abre a cualquier autenticado, sino SOLO a un correo.
--
--  >>> ANTES DE EJECUTAR: reemplaza CORREO_AUTORIZADO por el
--      correo de la única persona que podrá entrar. <<<
--      (El correo queda en tu base, no en el repositorio.)
-- ------------------------------------------------------------
alter table public.estudiantes enable row level security;
alter table public.sedes       enable row level security;

drop policy if exists "estudiantes_lectura"     on public.estudiantes;
drop policy if exists "estudiantes_actualizar"  on public.estudiantes;
drop policy if exists "sedes_lectura"           on public.sedes;

create policy "estudiantes_lectura" on public.estudiantes
  for select to authenticated
  using ((auth.jwt() ->> 'email') = 'CORREO_AUTORIZADO');

create policy "estudiantes_actualizar" on public.estudiantes
  for update to authenticated
  using ((auth.jwt() ->> 'email') = 'CORREO_AUTORIZADO')
  with check ((auth.jwt() ->> 'email') = 'CORREO_AUTORIZADO');

-- La app solo cambia la sede. RLS no puede filtrar por columna, así que se
-- limita el UPDATE a sede_id con privilegios de columna: un intento de tocar
-- cédula, nombres o correos desde la app recibe "permission denied" y falla.
-- El trigger corre como dueño de la tabla, así que puede seguir fijando
-- 'actualizado' sin que el llamante tenga ese privilegio.
revoke update on public.estudiantes from authenticated;
grant  update (sede_id) on public.estudiantes to authenticated;

create policy "sedes_lectura" on public.sedes
  for select to authenticated
  using ((auth.jwt() ->> 'email') = 'CORREO_AUTORIZADO');
