// lib/supabase.js
import { createClient } from '@supabase/supabase-js'

// Mengambil dari file .env (tanpa hardcode string langsung di file js)
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey)