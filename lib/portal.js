export async function loadMembers(page = 1, search = '', role = '', status = '') {
  const perPage = 8
  let query = supabase
    .from('members')
    .select('discord_id, discord_username, role, status, joined_at', { count: 'exact' })
    .order('joined_at', { ascending: false })
    .range((page - 1) * perPage, page * perPage - 1)

  if (search) query = query.or(`discord_username.ilike.%${search}%,discord_id.ilike.%${search}%`)
  if (role) query = query.eq('role', role)
  if (status) query = query.eq('status', status)

  const { data: rows, count: total, error } = await query
  if (error) return console.error('Gagal memuat member:', error.message)

  renderMemberTable(rows)
  renderPagination(total, page, perPage)
}