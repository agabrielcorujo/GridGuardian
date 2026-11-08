export const categories = ['HEALTHY', 'MAINTENANCE', 'DAMAGES', 'UNASSESSED'] as const
export type Category = typeof categories[number]
export const labels: Record<Category, string> = { HEALTHY: 'Healthy', MAINTENANCE: 'Maintenance', DAMAGES: 'Damaged', UNASSESSED: 'Unassessed' }
export const colors: Record<Category, string> = { HEALTHY: '#269b78', MAINTENANCE: '#d99b30', DAMAGES: '#da655c', UNASSESSED: '#94a3b8' }
export interface Report {
  report_id?: string; 'condition-timestamp': string; zipcode: string; timestamp: string
  classification: Category | null; severity: string; description?: string
  recommended_action?: string; issues_detected?: string[]; flight_id?: string; pole_id?: string
  location?: { latitude: number; longitude: number } | null
}
export interface Analytics {
  total_images: number; assessed_images: number; attention_required: number
  healthy_percentage: number | null; images_with_location: number; images_without_location: number
  by_classification: Record<Category, number>; daily: ({ date: string } & Record<Category, number>)[]
  latest_observation: string | null
}
export interface GeoData { type: 'FeatureCollection'; features: { type: 'Feature'; geometry: { type: 'Point'; coordinates: [number, number] }; properties: Report }[]; images_without_location: number; total_images: number }
export interface Page { items: Report[]; total: number; next_offset: number | null }
export interface Filters { zipcode: string; classification: string; severity: string; start: string; end: string; flight_id: string; pole_id: string }
export const initialFilters: Filters = { zipcode: '00901', classification: '', severity: '', start: '', end: '', flight_id: '', pole_id: '' }
export const reportKey = (r: Report) => `${r.zipcode}:${r['condition-timestamp']}`
export const categoryOf = (r: Report): Category => r.classification || 'UNASSESSED'
export const dateLabel = (value: string | null, detailed = false) => value ? new Date(value).toLocaleString('en-US', { month: 'short', day: 'numeric', ...(!detailed ? { timeZone: 'UTC' } : {}), ...(detailed ? { year: 'numeric', hour: 'numeric', minute: '2-digit' } : {}) }) : '—'
const base = import.meta.env.VITE_API_BASE_URL?.replace(/\/+$/, '')
export async function request<T>(route: string, filters: Filters, signal: AbortSignal, offset?: number): Promise<T> {
  if (!base) throw new Error('API URL is missing. Set VITE_API_BASE_URL in .env.local and restart the dev server.')
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(filters)) {
    if (key === 'zipcode' || !value) continue
    params.set(key, key === 'start' ? `${value}T00:00:00Z` : key === 'end' ? `${value}T23:59:59.999999Z` : value)
  }
  if (route === 'reports') { params.set('limit', '10'); params.set('offset', String(offset ?? 0)) }
  const response = await fetch(`${base}/${route}/${encodeURIComponent(filters.zipcode)}?${params}`, { signal })
  if (!response.ok) throw new Error(response.status === 422 ? 'These filters could not be applied. Check the ZIP code and date range.' : `The data service returned ${response.status}. Please try again.`)
  return response.json() as Promise<T>
}

export async function requestImage(report: Report, signal: AbortSignal): Promise<string> {
  if (!base) throw new Error('The image service is not configured.')
  const params = new URLSearchParams({ sort_key: report['condition-timestamp'] })
  const response = await fetch(`${base}/reports/${encodeURIComponent(report.zipcode)}/image?${params}`, { signal, cache: 'no-store' })
  if (!response.ok) throw new Error(response.status === 404 ? 'No image is available for this observation.' : 'The image could not be retrieved. Please try again.')
  const result = await response.json() as { url: string }
  if (typeof result.url !== 'string' || !result.url.startsWith('https://')) throw new Error('The image service returned an invalid link.')
  return result.url
}
