import { supabase } from './supebase.js'

export async function loginWithDiscord() {
  console.log('Fungsi loginWithDiscord mulai berjalan...')
  
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'discord',
    options: {
      redirectTo: `${window.location.origin}/shawbege-portal.html`
    }
  })

  if (error) {
    console.error('Supabase Auth Error:', error.message)
    alert('Gagal Login: ' + error.message)
  }
}
