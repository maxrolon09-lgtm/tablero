-- Mails seguidos (carpetas del bot que se muestran en el tablero)
create table if not exists mails (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  msg_id text not null,
  carpeta text default '',
  fecha timestamptz,
  de text default '', para text default '',
  asunto text default '', resumen text default '',
  adjuntos text default '', url text default '',
  monto numeric(16,2), moneda text default 'ARS', periodo text default '',
  enviado boolean default false,
  leido boolean default false, nota text default '',
  pago_id uuid references pagos on delete set null,
  espacio_id uuid references espacios on delete set null,
  creado timestamptz default now(),
  unique (owner, msg_id)
);
alter table mails enable row level security;
drop policy if exists solo_dueno on mails;
create policy solo_dueno on mails for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
revoke all on mails from anon;
create index if not exists mails_fecha_idx on mails(owner, carpeta, fecha desc);

create or replace function ingest_mails(p_token text, p_items jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare o uuid; n int := 0; it jsonb; pe uuid;
begin
  select owner into o from ingest_tokens where token = p_token;
  if o is null then raise exception 'clave inválida'; end if;
  select id into pe from espacios where owner = o and lower(nombre) = 'personal' limit 1;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into mails(owner, msg_id, carpeta, fecha, de, para, asunto, resumen, adjuntos, url, monto, moneda, periodo, enviado, espacio_id)
    values (o, it->>'msg_id', coalesce(it->>'carpeta',''), nullif(it->>'fecha','')::timestamptz,
            coalesce(it->>'de',''), coalesce(it->>'para',''), coalesce(it->>'asunto',''), coalesce(it->>'resumen',''),
            coalesce(it->>'adjuntos',''), coalesce(it->>'url',''), nullif(it->>'monto','')::numeric,
            coalesce(nullif(it->>'moneda',''),'ARS'), coalesce(it->>'periodo',''), coalesce((it->>'enviado')::boolean,false), pe)
    on conflict (owner, msg_id) do nothing;
    if found then n := n + 1; end if;
  end loop;
  update ingest_tokens set ultimo_uso = now() where owner = o;
  return n;
end $$;
revoke all on function ingest_mails(text, jsonb) from public;
grant execute on function ingest_mails(text, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
select 'ok' as resultado;
