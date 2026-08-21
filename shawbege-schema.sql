-- =====================================================================
-- ShawBege Community Web Portal — Database Schema (Supabase / PostgreSQL)
-- =====================================================================
-- Auth: Discord OAuth2 via Supabase Auth (auth.users bawaan Supabase).
-- Tabel "members" adalah profile 1:1 terhadap auth.users, diisi otomatis
-- lewat trigger saat user pertama kali login via Discord.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. ENUM TYPES
-- ---------------------------------------------------------------------
create type member_role as enum ('admin', 'pengurus_gudang', 'mekanik', 'moderator', 'member');
create type member_status as enum ('active', 'inactive');
create type item_category as enum ('ikan', 'material', 'komponen');
create type transaction_type as enum ('masuk', 'keluar');
create type stock_status as enum ('cukup', 'menipis', 'habis');
create type setoran_status as enum ('menunggu', 'terverifikasi', 'ditolak');


-- ---------------------------------------------------------------------
-- 1. MEMBER DIRECTORY  (PRD §4.B)
-- ---------------------------------------------------------------------
create table public.members (
  id              uuid primary key references auth.users(id) on delete cascade,
  discord_id      text unique not null,
  discord_username text not null,
  avatar_url      text,
  role            member_role not null default 'member',
  status          member_status not null default 'active',
  joined_at       timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index idx_members_role on public.members(role);
create index idx_members_status on public.members(status);

-- Auto-create a members row whenever someone logs in via Discord OAuth2.
create function public.handle_new_member()
returns trigger as $$
begin
  insert into public.members (id, discord_id, discord_username, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'provider_id',
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_member();


-- ---------------------------------------------------------------------
-- 2. WAREHOUSE — INVENTORY  (PRD §4.C.1)
-- ---------------------------------------------------------------------
create table public.fish_stock (
  id          uuid primary key default gen_random_uuid(),
  jenis_ikan  text not null,
  stok        integer not null default 0 check (stok >= 0),
  satuan      text not null default 'ekor',
  updated_by  uuid references public.members(id),
  updated_at  timestamptz not null default now()
);

create table public.materials (
  id          uuid primary key default gen_random_uuid(),
  nama        text not null,
  kategori    text not null,
  jumlah_unit integer not null default 0 check (jumlah_unit >= 0),
  satuan      text not null default 'unit',
  updated_by  uuid references public.members(id),
  updated_at  timestamptz not null default now()
);

create table public.components (
  id              uuid primary key default gen_random_uuid(),
  nama            text not null,
  kategori        text not null default 'Sparepart Umum',
  stok_cadangan   integer not null default 0 check (stok_cadangan >= 0),
  ambang_menipis  integer not null default 10,      -- threshold auto status
  status          stock_status generated always as (
                    case
                      when stok_cadangan = 0 then 'habis'
                      when stok_cadangan <= ambang_menipis then 'menipis'
                      else 'cukup'
                    end
                  ) stored,
  updated_by      uuid references public.members(id),
  updated_at      timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 3. WAREHOUSE — KAS & LOG TRANSAKSI  (PRD §4.C.1-2)
-- ---------------------------------------------------------------------
-- Saldo kas dihitung dari SUM(cash_transactions), bukan kolom statis,
-- supaya selalu konsisten dengan riwayat transaksi.
create table public.cash_transactions (
  id                uuid primary key default gen_random_uuid(),
  tipe              transaction_type not null,
  jumlah            numeric(14,2) not null check (jumlah > 0),
  deskripsi         text not null,
  penanggung_jawab  uuid not null references public.members(id),
  created_at        timestamptz not null default now()
);

-- Log gabungan untuk barang (ikan/material/komponen) — uang tetap di cash_transactions.
create table public.warehouse_logs (
  id                uuid primary key default gen_random_uuid(),
  kategori          item_category not null,
  item_id           uuid not null,          -- FK dinamis ke fish_stock / materials / components
  deskripsi         text not null,
  tipe              transaction_type not null,
  jumlah            integer not null,
  penanggung_jawab  uuid not null references public.members(id),
  created_at        timestamptz not null default now()
);

create index idx_warehouse_logs_kategori on public.warehouse_logs(kategori);
create index idx_warehouse_logs_created on public.warehouse_logs(created_at desc);

create view public.cash_balance as
select
  coalesce(sum(case when tipe = 'masuk' then jumlah else -jumlah end), 0) as saldo
from public.cash_transactions;


-- ---------------------------------------------------------------------
-- 4. WORKSHOP — MECHANIC INVENTORY  (PRD §4.D.1)
-- ---------------------------------------------------------------------
create table public.mechanic_inventory (
  id                    uuid primary key default gen_random_uuid(),
  komponen              text not null,
  dialokasikan_untuk    text not null,        -- mis. "Servis Rutin", "Servis Berat"
  stok                  integer not null default 0 check (stok >= 0),
  ambang_menipis        integer not null default 10,
  status                stock_status generated always as (
                          case
                            when stok = 0 then 'habis'
                            when stok <= ambang_menipis then 'menipis'
                            else 'cukup'
                          end
                        ) stored,
  updated_at            timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 5. WORKSHOP — SETORAN TRACKER  (PRD §4.D.2)
-- ---------------------------------------------------------------------
create table public.setoran (
  id           uuid primary key default gen_random_uuid(),
  mekanik_id   uuid not null references public.members(id),
  jumlah       numeric(14,2) not null check (jumlah > 0),
  catatan      text,
  status       setoran_status not null default 'menunggu',
  verified_by  uuid references public.members(id),
  tanggal      date not null default current_date,
  created_at   timestamptz not null default now()
);

create index idx_setoran_mekanik on public.setoran(mekanik_id);
create index idx_setoran_tanggal on public.setoran(tanggal desc);


-- ---------------------------------------------------------------------
-- 6. WORKSHOP — WORK LOGS  (PRD §4.D.3)
-- ---------------------------------------------------------------------
create table public.work_logs (
  id                    uuid primary key default gen_random_uuid(),
  mekanik_id            uuid not null references public.members(id),
  jenis_pekerjaan       text not null,
  klien_kendaraan       text,
  komponen_digunakan    jsonb not null default '[]',
  -- contoh isi: [{"component_id": "...", "nama": "Set Suspensi", "qty": 1}]
  tanggal               date not null default current_date,
  created_at            timestamptz not null default now()
);


-- =====================================================================
-- 7. ROW LEVEL SECURITY
-- =====================================================================
alter table public.members              enable row level security;
alter table public.fish_stock           enable row level security;
alter table public.materials            enable row level security;
alter table public.components           enable row level security;
alter table public.cash_transactions    enable row level security;
alter table public.warehouse_logs       enable row level security;
alter table public.mechanic_inventory   enable row level security;
alter table public.setoran              enable row level security;
alter table public.work_logs            enable row level security;

-- Helper: role milik user yang sedang login
create function public.current_role()
returns member_role as $$
  select role from public.members where id = auth.uid();
$$ language sql stable security definer;

-- Semua member terverifikasi boleh MELIHAT semua data (transparansi gudang).
create policy "members can read members"       on public.members            for select using (auth.role() = 'authenticated');
create policy "members can read fish_stock"    on public.fish_stock         for select using (auth.role() = 'authenticated');
create policy "members can read materials"     on public.materials          for select using (auth.role() = 'authenticated');
create policy "members can read components"    on public.components         for select using (auth.role() = 'authenticated');
create policy "members can read cash_tx"       on public.cash_transactions  for select using (auth.role() = 'authenticated');
create policy "members can read warehouse_logs" on public.warehouse_logs    for select using (auth.role() = 'authenticated');
create policy "members can read mechanic_inv"  on public.mechanic_inventory for select using (auth.role() = 'authenticated');
create policy "members can read setoran"       on public.setoran            for select using (auth.role() = 'authenticated');
create policy "members can read work_logs"     on public.work_logs          for select using (auth.role() = 'authenticated');

-- Hanya "pengurus_gudang" & "admin" yang boleh MENULIS data gudang.
create policy "gudang can write fish_stock" on public.fish_stock
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

create policy "gudang can write materials" on public.materials
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

create policy "gudang can write components" on public.components
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

create policy "gudang can write cash_tx" on public.cash_transactions
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

create policy "gudang can write warehouse_logs" on public.warehouse_logs
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

-- Mekanik boleh menulis setoran & work_logs milik diri sendiri; admin/pengurus bisa semua.
create policy "mekanik can insert own setoran" on public.setoran
  for insert with check (mekanik_id = auth.uid() or current_role() in ('pengurus_gudang','admin'));

create policy "gudang can verify setoran" on public.setoran
  for update using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

create policy "mekanik can insert own work_logs" on public.work_logs
  for insert with check (mekanik_id = auth.uid() or current_role() in ('pengurus_gudang','admin'));

create policy "mechanic_inventory writable by gudang" on public.mechanic_inventory
  for all using (current_role() in ('pengurus_gudang','admin'))
  with check (current_role() in ('pengurus_gudang','admin'));

-- Hanya admin yang boleh mengubah role/status member (verifikasi keanggotaan).
create policy "admin can update members" on public.members
  for update using (current_role() = 'admin')
  with check (current_role() = 'admin');
