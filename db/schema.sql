-- Tablero Max · estructura base
create extension if not exists pgcrypto;

create table if not exists espacios (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  nombre text not null,
  color text default '#4c8dff',
  orden int default 0,
  creado timestamptz default now()
);

create table if not exists proyectos (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete cascade,
  nombre text not null,
  descripcion text default '',
  estado text default 'Activo',
  objetivo date,
  creado timestamptz default now()
);

create table if not exists temas (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete set null,
  proyecto_id uuid references proyectos on delete set null,
  titulo text not null,
  area text default '',
  estado text default 'Pendiente',
  prioridad text default 'Media',
  contraparte text default '',
  alta date default current_date,
  objetivo date,
  descripcion text default '',
  tags text[] default '{}',
  cerrado_en timestamptz,
  creado timestamptz default now(),
  actualizado timestamptz default now()
);

create table if not exists pendientes (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  tema_id uuid not null references temas on delete cascade,
  texto text not null,
  hecho boolean default false,
  cierre timestamptz,
  creado timestamptz default now()
);

create table if not exists bitacora (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  tema_id uuid not null references temas on delete cascade,
  fecha timestamptz default now(),
  texto text not null,
  tipo text default 'usr'
);

create table if not exists pagos (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete set null,
  tema_id uuid references temas on delete set null,
  concepto text not null,
  categoria text default '',
  monto numeric(16,2) default 0,
  moneda text default 'ARS',
  vencimiento date,
  fecha_pago date,
  estado text default 'A pagar',
  medio text default '',
  recurrencia text default '',
  notas text default '',
  creado timestamptz default now()
);

create table if not exists recordatorios (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete set null,
  tema_id uuid references temas on delete set null,
  titulo text not null,
  fecha date not null,
  hora time,
  notas text default '',
  hecho boolean default false,
  creado timestamptz default now()
);

create table if not exists documentos (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete set null,
  tema_id uuid references temas on delete cascade,
  pago_id uuid references pagos on delete cascade,
  nombre text not null,
  categoria text default 'Documento',
  nota text default '',
  path text,
  url text,
  size bigint,
  mime text,
  creado timestamptz default now()
);

-- Seguridad: cada fila solo la ve y modifica su dueño
do $$
declare t text;
begin
  foreach t in array array['espacios','proyectos','temas','pendientes','bitacora','pagos','recordatorios','documentos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists solo_dueno on %I', t);
    execute format('create policy solo_dueno on %I for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid())', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

create index if not exists temas_owner_idx on temas(owner);
create index if not exists pend_tema_idx on pendientes(tema_id);
create index if not exists bit_tema_idx on bitacora(tema_id);
create index if not exists pagos_venc_idx on pagos(owner, vencimiento);
create index if not exists rec_fecha_idx on recordatorios(owner, fecha);
create index if not exists docs_tema_idx on documentos(tema_id);

-- Archivos: bucket privado, carpeta por usuario
insert into storage.buckets (id, name, public, file_size_limit)
values ('docs','docs', false, 52428800)
on conflict (id) do nothing;

drop policy if exists docs_dueno_sel on storage.objects;
drop policy if exists docs_dueno_ins on storage.objects;
drop policy if exists docs_dueno_upd on storage.objects;
drop policy if exists docs_dueno_del on storage.objects;
create policy docs_dueno_sel on storage.objects for select to authenticated using (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy docs_dueno_ins on storage.objects for insert to authenticated with check (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy docs_dueno_upd on storage.objects for update to authenticated using (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy docs_dueno_del on storage.objects for delete to authenticated using (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);

select 'ok' as resultado;
