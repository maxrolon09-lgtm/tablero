-- Cuentas / Destinatarios
create table if not exists cuentas (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  espacio_id uuid references espacios on delete set null,
  nombre text not null,
  categoria text default '',
  titular text default '',
  cuit text default '',
  banco text default '',
  cbu text default '',
  alias text default '',
  nro_cliente text default '',
  contacto text default '',
  notas text default '',
  monto_habitual numeric(16,2),
  moneda text default 'ARS',
  recurrencia text default '',
  medio text default '',
  activa boolean default true,
  creado timestamptz default now()
);
alter table cuentas enable row level security;
drop policy if exists solo_dueno on cuentas;
create policy solo_dueno on cuentas for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
revoke all on cuentas from anon;
alter table pagos add column if not exists cuenta_id uuid references cuentas on delete set null;
create index if not exists pagos_cuenta_idx on pagos(cuenta_id);
create index if not exists cuentas_owner_idx on cuentas(owner);
select 'ok' as resultado;
