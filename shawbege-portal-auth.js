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
