import { supabase } from './lib/supabase.js'

// Load jumlah member & setoran
async function loadPublicStats() {
  const [{ count: totalMember }, { count: totalSetoran }] = await Promise.all([
    supabase.from('members').select('*', { count: 'exact', head: true }).eq('status', 'active'),
    supabase.from('setoran').select('*', { count: 'exact', head: true }).eq('status', 'terverifikasi'),
  ])

  // Render ke elemen HTML
  document.getElementById('stat-members').textContent = totalMember || 0
  document.getElementById('stat-setoran').textContent = totalSetoran || 0
}

// Langganan pembaruan aktivitas secara Realtime
function subscribeRealtimeTicker() {
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
}

function pushToTicker(entry) {
  const tickerTrack = document.querySelector('.ticker-track')
  if (!tickerTrack) return

  const item = document.createElement('div')
  item.className = 'ticker-item'
  item.textContent = `[${entry.tipe.toUpperCase()}] ${entry.deskripsi}`
  tickerTrack.prepend(item)
}

// Jalankan saat landing page dimuat
document.addEventListener('DOMContentLoaded', () => {
  loadPublicStats()
  subscribeRealtimeTicker()
})