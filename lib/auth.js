async function loginWithDiscord() {
  await supabase.auth.signInWithOAuth({
    provider: 'discord',
    options: {
      // Mengarahkan balik ke domain utama (https://shawi.vercel.app/)
      redirectTo: window.location.origin 
    }
  });
}
