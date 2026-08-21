# ShawBege — Supabase API Reference

Dokumen ini berisi query siap pakai (`@supabase/supabase-js` v2) untuk menyambungkan
`shawbege-landing.html` dan `shawbege-portal.html` ke schema di `shawbege-schema.sql`.

---

## 0. Setup

```bash
npm install @supabase/supabase-js
```

```js
// lib/supabase.js
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

`SUPABASE_URL` dan `SUPABASE_ANON_KEY` diambil dari **Project Settings → API** di dashboard
Supabase. Anon key aman dipakai di frontend karena akses data tetap dibatasi oleh RLS
policy yang sudah didefinisikan di schema.

---

## 1. Autentikasi (Discord OAuth2)

Aktifkan provider di **Authentication → Providers → Discord**, isi Client ID/Secret dari
[Discord Developer Portal](https://discord.com/developers/applications), lalu set
Redirect URL sesuai domain Vercel kamu.

```js
// Login
async function loginWithDiscord() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'discord',
    options: { redirectTo: `${window.location.origin}/portal` }
  })
  if (error) console.error(error.message)
}

// Logout — dipakai di tombol "Keluar" pada top bar portal
async function logout() {
  await supabase.auth.signOut()
  window.location.href = '/'
}

// Ambil session & profil member yang sedang login (untuk kartu profil di sidebar)
async function getCurrentMember() {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('members')
    .select('discord_username, avatar_url, role, status')
    .eq('id', session.user.id)
    .single()

  if (error) console.error(error.message)
  return data
}

// Redirect otomatis kalau belum login — panggil di awal load shawbege-portal.html
supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_OUT' || !session) window.location.href = '/'
})
```

---

## 2. Member Directory

Mengganti data dummy `members[]` di `shawbege-portal.html`.

```js
// List + search + filter (dipakai untuk memberSearch / memberRole / memberStatus)
async function fetchMembers({ search = '', role = '', status = '', page = 1, perPage = 8 }) {
  let query = supabase
    .from('members')
    .select('discord_id, discord_username, role, status, joined_at', { count: 'exact' })
    .order('joined_at', { ascending: false })
    .range((page - 1) * perPage, page * perPage - 1)

  if (search) query = query.or(`discord_username.ilike.%${search}%,discord_id.ilike.%${search}%`)
  if (role) query = query.eq('role', role)
  if (status) query = query.eq('status', status)

  const { data, count, error } = await query
  if (error) throw error
  return { rows: data, total: count }
}

// Ubah role/status member — hanya berhasil jika current user 'admin' (ditegakkan oleh RLS)
async function updateMember(memberId, changes) {
  const { error } = await supabase.from('members').update(changes).eq('id', memberId)
  if (error) throw error
}
```

---

## 3. Warehouse Management

### 3.1 Inventaris (Ikan / Material / Komponen)

```js
const fetchFishStock  = () => supabase.from('fish_stock').select('*').order('jenis_ikan')
const fetchMaterials  = () => supabase.from('materials').select('*').order('nama')
const fetchComponents = () => supabase.from('components').select('*').order('nama')
// .select('*') pada 'components' otomatis membawa kolom 'status' (generated column)

// Update stok — dipanggil dari form input pengurus gudang
async function adjustFishStock(id, deltaQty, penanggungJawabId, deskripsi) {
  const { data: item } = await supabase.from('fish_stock').select('stok').eq('id', id).single()
  const { error } = await supabase.from('fish_stock')
    .update({ stok: item.stok + deltaQty, updated_by: penanggungJawabId, updated_at: new Date() })
    .eq('id', id)
  if (error) throw error

  // catat ke log transaksi gudang sekaligus
  await supabase.from('warehouse_logs').insert({
    kategori: 'ikan', item_id: id, deskripsi,
    tipe: deltaQty > 0 ? 'masuk' : 'keluar',
    jumlah: Math.abs(deltaQty), penanggung_jawab: penanggungJawabId
  })
}
```

### 3.2 Kas & Log Transaksi

```js
// Saldo kas — pakai view 'cash_balance' dari schema, bukan hitung manual di frontend
const fetchCashBalance = async () => {
  const { data, error } = await supabase.from('cash_balance').select('saldo').single()
  if (error) throw error
  return data.saldo
}

async function recordCashTransaction({ tipe, jumlah, deskripsi, penanggungJawabId }) {
  const { error } = await supabase.from('cash_transactions')
    .insert({ tipe, jumlah, deskripsi, penanggung_jawab: penanggungJawabId })
  if (error) throw error
}

// Log transaksi gabungan (barang + uang) untuk tabel "Log Transaksi"
const fetchWarehouseLogs = (limit = 20) =>
  supabase.from('warehouse_logs')
    .select('*, penanggung_jawab:members(discord_username)')
    .order('created_at', { ascending: false })
    .limit(limit)
```

### 3.3 Realtime — untuk strip ticker "live" di landing page

```js
// Menggantikan data statis pada .ticker-track di shawbege-landing.html
supabase
  .channel('warehouse-activity')
  .on('postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'warehouse_logs' },
    (payload) => pushToTicker(payload.new)
  )
  .on('postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'cash_transactions' },
    (payload) => pushToTicker(payload.new)
  )
  .subscribe()

function pushToTicker(entry) {
  // render item baru ke .ticker-track tanpa reload halaman
}
```

---

## 4. Workshop Center

```js
// Mechanic Inventory
const fetchMechanicInventory = () =>
  supabase.from('mechanic_inventory').select('*').order('komponen')

// Setoran — form "Catat Setoran" di shawbege-portal.html
async function submitSetoran({ mekanikId, jumlah, catatan }) {
  const { error } = await supabase.from('setoran')
    .insert({ mekanik_id: mekanikId, jumlah, catatan })  // status default 'menunggu'
  if (error) throw error
}

// Rekap setoran (join ke nama mekanik)
const fetchSetoran = () =>
  supabase.from('setoran')
    .select('id, jumlah, status, tanggal, mekanik:members(discord_username)')
    .order('tanggal', { ascending: false })

// Verifikasi setoran — hanya pengurus_gudang/admin (ditegakkan RLS)
async function verifySetoran(setoranId, verifierId, approve = true) {
  const { error } = await supabase.from('setoran')
    .update({ status: approve ? 'terverifikasi' : 'ditolak', verified_by: verifierId })
    .eq('id', setoranId)
  if (error) throw error
}

// Work Logs
async function submitWorkLog({ mekanikId, jenisPekerjaan, klienKendaraan, komponenDigunakan }) {
  const { error } = await supabase.from('work_logs').insert({
    mekanik_id: mekanikId,
    jenis_pekerjaan: jenisPekerjaan,
    klien_kendaraan: klienKendaraan,
    komponen_digunakan: komponenDigunakan  // array of {component_id, nama, qty}
  })
  if (error) throw error
}

const fetchWorkLogs = () =>
  supabase.from('work_logs')
    .select('*, mekanik:members(discord_username)')
    .order('tanggal', { ascending: false })
```

---

## 5. Statistik publik untuk Landing Page

Query ini boleh diakses tanpa login (buat endpoint terpisah / RPC dengan `security definer`
jika ingin membatasi field yang diekspos ke publik).

```js
async function fetchPublicStats() {
  const [{ count: totalMember }, { count: totalSetoran }] = await Promise.all([
    supabase.from('members').select('*', { count: 'exact', head: true }).eq('status', 'active'),
    supabase.from('setoran').select('*', { count: 'exact', head: true }).eq('status', 'terverifikasi'),
  ])
  return { totalMember, totalSetoran }
}
```

---

## 6. Catatan Implementasi

- Semua fungsi di atas mengasumsikan `supabase` sudah diinisialisasi dan user sudah login
  (session tersedia) — jalankan `getCurrentMember()` dulu di awal load `shawbege-portal.html`
  dan redirect ke landing page kalau `null`.
- RLS di schema sudah menegakkan siapa boleh apa; kode frontend di atas **tidak perlu**
  cek role manual sebelum query tulis — cukup tangani error yang dikembalikan Supabase
  kalau policy menolak (`error.code === '42501'`).
- Untuk paginasi Member Directory yang sebelumnya dekoratif, `fetchMembers()` di atas
  sudah pakai `.range()` + `count: 'exact'` sehingga tombol halaman 1/2/3 bisa dihubungkan
  langsung ke parameter `page`.
