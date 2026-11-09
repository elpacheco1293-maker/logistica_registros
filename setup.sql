-- NEXOCORP · Registro de devolución de psicotrópicos
-- Pega todo esto en Supabase > SQL Editor y ejecútalo una sola vez.
-- Después: Authentication > Providers > Email > desactiva "Allow new users to sign up"
-- y crea tu usuario administrador en Authentication > Users.

create table if not exists catalogo (
  codigo text primary key,
  descripcion text,
  unidad text,
  proveedor text,
  politica text
);

create table if not exists registros (
  id bigint generated always as identity primary key,
  bodega text not null,
  codigo text not null references catalogo(codigo),
  descripcion text,
  proveedor text,
  unidad text,
  lote text not null,
  caducidad text not null,
  cantidad int not null check (cantidad > 0),
  factura text not null,
  politica text,
  created_at timestamptz default now(),
  unique (bodega, codigo)
);

-- Seguridad: las bodegas (anon) no pueden leer ni escribir tablas directamente.
-- Solo el administrador autenticado ve y edita todo.
alter table catalogo enable row level security;
alter table registros enable row level security;
drop policy if exists admin_catalogo on catalogo;
drop policy if exists admin_registros on registros;
create policy admin_catalogo on catalogo for all to authenticated using (true) with check (true);
create policy admin_registros on registros for all to authenticated using (true) with check (true);

-- Las bodegas solo usan estas dos funciones.
create or replace function buscar_producto(p_bodega text, p_codigo text)
returns json language plpgsql security definer set search_path = public as $$
declare c catalogo;
begin
  select * into c from catalogo where codigo = trim(p_codigo);
  if not found then return json_build_object('encontrado', false); end if;
  return json_build_object(
    'encontrado', true,
    'descripcion', c.descripcion,
    'proveedor', c.proveedor,
    'unidad', c.unidad,
    'ya_registrado', exists (select 1 from registros r where r.bodega = upper(trim(p_bodega)) and r.codigo = c.codigo)
  );
end $$;

create or replace function registrar(p_bodega text, p_codigo text, p_lote text, p_caducidad text, p_cantidad int, p_factura text)
returns json language plpgsql security definer set search_path = public as $$
declare c catalogo;
begin
  if coalesce(trim(p_bodega),'') = '' or coalesce(trim(p_lote),'') = '' or coalesce(p_caducidad,'') = ''
     or coalesce(p_cantidad,0) <= 0 or coalesce(trim(p_factura),'') = '' then
    return json_build_object('ok', false, 'error', 'datos');
  end if;
  select * into c from catalogo where codigo = trim(p_codigo);
  if not found then return json_build_object('ok', false, 'error', 'codigo'); end if;
  begin
    insert into registros (bodega, codigo, descripcion, proveedor, unidad, lote, caducidad, cantidad, factura, politica)
    values (upper(trim(p_bodega)), c.codigo, c.descripcion, c.proveedor, c.unidad, trim(p_lote), p_caducidad, p_cantidad, trim(p_factura), c.politica);
  exception when unique_violation then
    return json_build_object('ok', false, 'error', 'duplicado');
  end;
  return json_build_object('ok', true);
end $$;

revoke all on function buscar_producto(text, text) from public;
revoke all on function registrar(text, text, text, text, int, text) from public;
grant execute on function buscar_producto(text, text) to anon, authenticated;
grant execute on function registrar(text, text, text, text, int, text) to anon, authenticated;

-- Productos iniciales (luego cargas tu data completa desde el panel).
insert into catalogo (codigo, descripcion, unidad, proveedor, politica) values
 ('7800026007471', 'ANSIOPLAN_ODT 10MGX30 COMP DISP CLOTIAZEPAM(PSICO)', 'Tabletas', 'PHARMATECH BOLIVIANA SA.', 'EN EL MES'),
 ('7794433109173', 'DIOCAM 2MG X 30 COMP (PSICO) CLONAZEPAM', 'Tabletas', 'GADOR', '3 MESES ANTES')
on conflict (codigo) do nothing;
