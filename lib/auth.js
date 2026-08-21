import { supabase } from './supabase.js'

export async function loginWithDiscord() {
  console.log('Fungsi loginWithDiscord mulai berjalan...')
  
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'discord',
    options: {
      redirectTo: `https://shawi.vercel.app`
    }
  })

  if (error) {
    console.error('Supabase Auth Error:', error.message)
    alert('Gagal Login: ' + error.message)
  }
}
