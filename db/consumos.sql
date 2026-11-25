-- Consumos (avisos de Santander leídos desde Gmail)
create table if not exists consumos (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  msg_id text not null,
  fecha date, hora time,
  tipo text default 'otro', tarjeta text default '', ultimos4 text default '',
  comercio text default '', comercio_detalle text default '',
  monto numeric(16,2), moneda text default 'ARS', cuotas int,
  asunto text default '', categoria text default '', notas text default '',
  espacio_id uuid references espacios on delete set null,
  creado timestamptz default now(),
  unique (owner, msg_id)
);
alter table consumos enable row level security;
drop policy if exists solo_dueno on consumos;
create policy solo_dueno on consumos for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
revoke all on consumos from anon;
create index if not exists consumos_fecha_idx on consumos(owner, fecha);

-- Clave del lector (solo permite cargar consumos)
create table if not exists ingest_tokens (
  owner uuid primary key references auth.users on delete cascade,
  token text not null unique,
  creado timestamptz default now(),
  ultimo_uso timestamptz
);
alter table ingest_tokens enable row level security;
revoke all on ingest_tokens from anon, authenticated;

create or replace function get_ingest_token(regenerar boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if auth.uid() is null then raise exception 'no autenticado'; end if;
  if regenerar then delete from ingest_tokens where owner = auth.uid(); end if;
  select token into t from ingest_tokens where owner = auth.uid();
  if t is null then
    t := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into ingest_tokens(owner, token) values (auth.uid(), t);
  end if;
  return t;
end $$;
revoke all on function get_ingest_token(boolean) from public, anon;
grant execute on function get_ingest_token(boolean) to authenticated;

create or replace function lector_estado()
returns timestamptz language sql security definer set search_path = public as $$
  select ultimo_uso from ingest_tokens where owner = auth.uid();
$$;
revoke all on function lector_estado() from public, anon;
grant execute on function lector_estado() to authenticated;

create or replace function ingest_consumos(p_token text, p_items jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare o uuid; n int := 0; it jsonb; pe uuid;
begin
  select owner into o from ingest_tokens where token = p_token;
  if o is null then raise exception 'clave inválida'; end if;
  select id into pe from espacios where owner = o and lower(nombre) = 'personal' limit 1;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into consumos(owner, msg_id, fecha, hora, tipo, tarjeta, ultimos4, comercio, comercio_detalle, monto, moneda, cuotas, asunto, espacio_id)
    values (o, it->>'msg_id', nullif(it->>'fecha','')::date, nullif(it->>'hora','')::time,
            coalesce(nullif(it->>'tipo',''),'otro'), coalesce(it->>'tarjeta',''), coalesce(it->>'ultimos4',''),
            coalesce(it->>'comercio',''), coalesce(it->>'comercio_detalle',''),
            nullif(it->>'monto','')::numeric, coalesce(nullif(it->>'moneda',''),'ARS'),
            nullif(it->>'cuotas','')::int, coalesce(it->>'asunto',''), pe)
    on conflict (owner, msg_id) do nothing;
    if found then n := n + 1; end if;
  end loop;
  update ingest_tokens set ultimo_uso = now() where owner = o;
  return n;
end $$;
revoke all on function ingest_consumos(text, jsonb) from public;
grant execute on function ingest_consumos(text, jsonb) to anon, authenticated;

select 'ok' as resultado;
