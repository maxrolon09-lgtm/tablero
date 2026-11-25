-- Destinatarios habituales: vincular movimientos (transferencias / consumos) con cuentas y pagos
alter table cuentas add column if not exists destinatarios text default '';
alter table consumos add column if not exists cuenta_id uuid references cuentas on delete set null;
alter table consumos add column if not exists pago_id uuid references pagos on delete set null;
notify pgrst, 'reload schema';
select 'ok' as resultado;
