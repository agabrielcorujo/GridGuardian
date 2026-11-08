import { useCallback, useEffect, useRef, useState } from 'react'
import { Activity, ArrowDownToLine, ArrowRight, ArrowUpRight, CalendarDays, Check, ChevronLeft, ChevronRight, CircleHelp, ClipboardList, Filter, LayoutDashboard, MapPin, Radio, RefreshCw, Search, ShieldCheck, SlidersHorizontal, TriangleAlert, X } from 'lucide-react'
import InspectionMap from './components/InspectionMap'
import InspectionImage from './components/InspectionImage'
import { categories, categoryOf, colors, dateLabel, initialFilters, labels, reportKey, request } from './api'
import type { Analytics, Filters, GeoData, Page, Report } from './api'
import './App.css'

function Badge({ report }: { report: Report }) { const category = categoryOf(report); return <span className={`badge ${category.toLowerCase()}`}><i />{labels[category]}</span> }
const number = (n: number | undefined) => n == null ? '—' : n.toLocaleString()
const demoZipcodes = ['00680', '00612', '00901', '00730', '00725']

function App() {
  const [draft, setDraft] = useState<Filters>(initialFilters)
  const [filters, setFilters] = useState<Filters>(initialFilters)
  const [advanced, setAdvanced] = useState(false)
  const [data, setData] = useState<{ analytics: Analytics; geo: GeoData; page: Page } | null>(null)
  const [selected, setSelected] = useState<Report | null>(null)
  const [focused, setFocused] = useState<Report | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [offset, setOffset] = useState(0)
  const [refresh, setRefresh] = useState(0)
  const [updated, setUpdated] = useState<Date | null>(null)
  const [view, setView] = useState('overview')
  const [help, setHelp] = useState(false)
  const [search, setSearch] = useState('')
  const [formError, setFormError] = useState('')
  const [exporting, setExporting] = useState(false)
  const exportAbort = useRef<AbortController | null>(null)
  useEffect(() => () => exportAbort.current?.abort(), [])
  useEffect(() => {
    if (!selected && !help) return
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { setSelected(null); setHelp(false) }
      if (event.key !== 'Tab') return
      const dialog = document.querySelector('[role="dialog"]')
      const elements = dialog?.querySelectorAll<HTMLElement>('button:not(:disabled), a[href], input, select, [tabindex="0"]')
      if (!elements?.length) return
      const first = elements[0], last = elements[elements.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', handleKey)
    return () => { document.body.style.overflow = previousOverflow; document.removeEventListener('keydown', handleKey) }
  }, [selected, help])
  useEffect(() => {
    const controller = new AbortController()
    setLoading(true); setError(''); setData(null); setSelected(null); setFocused(null)
    Promise.all([
      request<Analytics>('analytics', filters, controller.signal),
      request<GeoData>('map', filters, controller.signal),
      request<Page>('reports', filters, controller.signal, offset),
    ]).then(([analytics, geo, page]) => { setData({ analytics, geo, page }); setUpdated(new Date()) })
      .catch(e => { if (e.name !== 'AbortError') setError(e instanceof TypeError ? 'Unable to reach the data service. Check your connection and the API’s CORS settings, then retry.' : e.message) })
      .finally(() => { if (!controller.signal.aborted) setLoading(false) })
    return () => controller.abort()
  }, [filters, offset, refresh])
  const onSelect = useCallback((report: Report) => setSelected(report), [])
  const change = (key: keyof Filters, value: string) => setDraft(previous => ({ ...previous, [key]: value }))
  const apply = (e: React.FormEvent) => {
    e.preventDefault()
    if (!demoZipcodes.includes(draft.zipcode)) { setFormError('Choose a ZIP code from the list.'); return }
    if (draft.start && draft.end && draft.start > draft.end) { setFormError('The start date must be before the end date.'); return }
    setFormError(''); setOffset(0); setSearch(''); setFilters({ ...draft, flight_id: draft.flight_id.trim(), pole_id: draft.pole_id.trim() })
  }
  const reset = () => { setDraft(initialFilters); setFilters(initialFilters); setOffset(0); setSearch(''); setFormError('') }
  const exportCsv = async () => {
    const controller = new AbortController(); exportAbort.current = controller; setExporting(true)
    try {
      const rows: Report[] = []
      let next: number | null = 0
      while (next !== null) {
        const page: Page = await request<Page>('reports', filters, controller.signal, next)
        rows.push(...page.items)
        if (page.next_offset !== null && page.next_offset <= next) throw new Error('Export stopped because pagination did not advance.')
        next = page.next_offset
      }
      const fields = ['report_id', 'zipcode', 'timestamp', 'classification', 'severity', 'pole_id', 'flight_id', 'description', 'recommended_action', 'latitude', 'longitude']
      const quote = (value: unknown) => { let text = String(value ?? ''); if (/^[=+@\-\t\r]/.test(text)) text = "'" + text; return '"' + text.replaceAll('"', '""') + '"' }
      const csv = [fields.join(','), ...rows.map(r => fields.map(f => quote(f === 'latitude' ? r.location?.latitude : f === 'longitude' ? r.location?.longitude : r[f as keyof Report])).join(','))].join('\r\n')
      const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' })); const link = document.createElement('a'); link.href = url; link.download = `gridguardian-${filters.zipcode}.csv`; link.click(); URL.revokeObjectURL(url)
    } catch (e) { if (e instanceof Error && e.name !== 'AbortError') setError(`Export failed: ${e.message}`) }
    finally { setExporting(false) }
  }
  const analytics = data?.analytics
  const reports = data?.page.items.filter(r => `${r.pole_id || ''} ${r.report_id || ''} ${r.description || ''}`.toLowerCase().includes(search.toLowerCase())) ?? []
  const total = analytics?.total_images ?? 0
  const activeFilters = Object.entries(filters).filter(([k, v]) => k !== 'zipcode' && v).length
  const dailyMax = Math.max(1, ...(analytics?.daily.map(d => categories.reduce((n, c) => n + d[c], 0)) ?? []))
  const navigation = [{ id: 'overview', label: 'Overview', icon: LayoutDashboard }, { id: 'map', label: 'Infrastructure map', icon: MapPin }, { id: 'reports', label: 'Inspections', icon: ClipboardList }]
  return <div className="app-shell">
    <aside className="sidebar"><a className="brand" href="#" aria-label="GridGuardian overview" onClick={e => { e.preventDefault(); setView('overview') }}><span className="brand-mark"><img src="/gridguardian.svg" alt="" aria-hidden="true" /></span><span>Grid<span className="brand-light">Guardian</span><small>INFRASTRUCTURE INTELLIGENCE</small></span></a>
      <div className="workspace"><span className="workspace-icon">PR</span><div>Puerto Rico<small>Utility operations</small></div><Radio size={15} /></div>
      <p className="nav-label">WORKSPACE</p><nav>{navigation.map(n => <button key={n.id} className={view === n.id ? 'nav-item active' : 'nav-item'} onClick={() => setView(n.id)}><n.icon size={18} />{n.label}{view === n.id && <span className="nav-dot" />}</button>)}</nav>
      <div className="sidebar-bottom"><div className="region-note"><span className="eyebrow">A CLEARER PICTURE</span><p>Better visibility.<br />Stronger infrastructure.</p><span>Drone-powered visual assessments</span><ShieldCheck size={25} /></div><button className="help-button" onClick={() => setHelp(true)}><CircleHelp size={18} /> Dashboard guide <ArrowUpRight size={15} /></button><div className="sidebar-footer"><span className="live-dot" /> GridGuardian <span>v1.0</span></div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div><span className="muted">Workspace</span><ChevronRight size={14} /><span>{navigation.find(n => n.id === view)?.label}</span></div><span className="region-chip"><MapPin size={13} /> Puerto Rico, US</span></header>
      <main><div className="page-heading"><div><span className="eyebrow">GRID INTELLIGENCE / PUERTO RICO</span><h1>{view === 'overview' ? 'Infrastructure overview' : view === 'map' ? 'Infrastructure map' : 'Inspection reports'}<span className="live-label"><i />Live data</span></h1><p>A clear view of your infrastructure. From the air to the ground.</p></div><div className="heading-actions"><button className="button icon-button" aria-label="Refresh data" disabled={loading} onClick={() => setRefresh(v => v + 1)}><RefreshCw size={16} className={loading ? 'spin' : ''} /></button><button className="button" disabled={loading || !data || exporting} onClick={exportCsv}><ArrowDownToLine size={16} />{exporting ? 'Exporting…' : 'Export data'}</button></div></div>
      <form className="filter-panel" onSubmit={apply}><div className="filter-main"><label className="zip-field"><MapPin size={16} /><span>ZIP CODE</span><select aria-label="Puerto Rico ZIP code" value={draft.zipcode} onChange={e => change('zipcode', e.target.value)} required>{demoZipcodes.map(zip => <option key={zip} value={zip}>{zip}</option>)}</select></label><label><span>CONDITION</span><select value={draft.classification} onChange={e => change('classification', e.target.value)}><option value="">All conditions</option>{categories.map(c => <option key={c} value={c}>{labels[c]}</option>)}</select></label><label className="date-field"><span>FROM · UTC</span><input aria-label="Start date" type="date" value={draft.start} onChange={e => change('start', e.target.value)} /></label><label className="date-field"><span>TO · UTC</span><input aria-label="End date" type="date" value={draft.end} onChange={e => change('end', e.target.value)} /></label><button type="button" className={`button more-filter ${advanced ? 'selected' : ''}`} onClick={() => setAdvanced(v => !v)} aria-expanded={advanced}><SlidersHorizontal size={16} /><span>More filters</span>{activeFilters > 0 && <b>{activeFilters}</b>}</button><button className="button primary" type="submit"><Filter size={15} />Apply filters</button></div>
      {advanced && <div className="advanced-filters"><label><span>SEVERITY</span><select value={draft.severity} onChange={e => change('severity', e.target.value)}><option value="">All severities</option><option value="HIGH">High</option><option value="MEDIUM">Medium</option><option value="NONE">None</option><option value="UNKNOWN">Unknown</option></select></label><label><span>FLIGHT ID</span><input value={draft.flight_id} onChange={e => change('flight_id', e.target.value)} placeholder="Exact flight ID" /></label><label><span>POLE ID</span><input value={draft.pole_id} onChange={e => change('pole_id', e.target.value)} placeholder="Exact pole ID" /></label><button type="button" className="text-button" onClick={reset}>Reset filters</button></div>}{formError && <p className="form-error" role="alert">{formError}</p>}</form>
      <div className="scope-line"><span><span className="live-dot" />{loading ? 'Updating observations…' : `ZIP ${filters.zipcode} · ${number(analytics?.total_images)} image observations`}{activeFilters > 0 && ' · Filtered view'}</span><span>{updated && !loading ? `Updated ${updated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : 'Connecting to data service'}</span></div>
      {error && <div className="error-banner" role="alert"><TriangleAlert size={18} /><span>{error}</span><button onClick={() => setRefresh(v => v + 1)}>Retry</button></div>}
      <div aria-busy={loading}>
      {view === 'overview' && <><section className="metrics-grid" aria-label="Key metrics">{[
        { name: 'Total observations', value: number(analytics?.total_images), hint: `${number(analytics?.assessed_images)} assessable images`, icon: ClipboardList, tone: 'blue' },
        { name: 'Healthy infrastructure', value: analytics ? (analytics.healthy_percentage == null ? '—' : `${analytics.healthy_percentage}%`) : '—', hint: `${number(analytics?.by_classification.HEALTHY)} healthy observations`, icon: ShieldCheck, tone: 'green' },
        { name: 'Needs attention', value: number(analytics?.attention_required), hint: 'Maintenance + damaged', icon: TriangleAlert, tone: 'amber' },
        { name: 'Mapped observations', value: number(analytics?.images_with_location), hint: `${number(analytics?.images_without_location)} without GPS coordinates`, icon: MapPin, tone: 'violet' },
      ].map(m => <article className="metric-card" key={m.name}><div className="metric-label">{m.name}<span className={`metric-icon ${m.tone}`}><m.icon size={17} /></span></div><strong className={loading ? 'loading-value' : ''}>{loading ? '—' : m.value}</strong><span className="metric-hint">{m.hint}</span></article>)}</section></>}
      {view !== 'reports' && <section className={`visual-grid ${view === 'map' ? 'map-only' : ''}`}><article className="panel map-panel"><div className="panel-heading"><div><h2>Infrastructure map <span className="count-tag">{number(data?.geo.features.length)} locations</span></h2><p>Explore image assessments across Puerto Rico</p></div><span className="map-live"><i />Geospatial view</span></div><InspectionMap data={data?.geo ?? null} selected={focused ?? selected} onSelect={onSelect} /><div className="map-footer"><span><Radio size={13} /> Select a marker to inspect an observation</span><span>{number(analytics?.images_without_location)} missing GPS</span></div></article>
      {view === 'overview' && <article className="panel condition-panel"><div className="panel-heading"><div><h2>Condition breakdown</h2><p>Visual assessment distribution</p></div><Activity size={18} className="muted" /></div><div className="donut-area"><div className="donut" style={{ background: total ? `conic-gradient(${categories.map((c, i) => `${colors[c]} ${100 * categories.slice(0, i).reduce((n, k) => n + (analytics?.by_classification[k] ?? 0), 0) / total}% ${100 * categories.slice(0, i + 1).reduce((n, k) => n + (analytics?.by_classification[k] ?? 0), 0) / total}%`).join(',')})` : '#edf1f3' }}><div><strong>{number(analytics?.total_images)}</strong><span>observations</span></div></div></div><div className="condition-list">{categories.map(c => <button key={c} title={`Filter by ${labels[c]}`} onClick={() => { setDraft(v => ({ ...v, classification: c })); setFilters(v => ({ ...v, classification: c })); setOffset(0) }}><span><i style={{ background: colors[c] }} />{labels[c]}</span><strong>{number(analytics?.by_classification[c])}</strong><small>{total ? Math.round(100 * (analytics?.by_classification[c] ?? 0) / total) : 0}%</small></button>)}</div><p className="panel-footnote">Image assessments, not a unique asset inventory.</p></article>}</section>}
      {view === 'overview' && <section className="panel activity-panel"><div className="panel-heading"><div><h2>Observation activity</h2><p>Daily image assessments · UTC</p></div><span className="subtle-chip"><CalendarDays size={13} />{analytics?.daily.length ? `${dateLabel(analytics.daily[0].date + 'T00:00:00Z')} — ${dateLabel(analytics.daily.at(-1)!.date + 'T00:00:00Z')}` : 'No observations'}</span></div><div className="activity-chart">{analytics?.daily.length ? analytics.daily.map(d => <div key={d.date} className="chart-column" title={`${d.date}: ${categories.reduce((n, c) => n + d[c], 0)} observations`}><span className="bar-total">{categories.reduce((n, c) => n + d[c], 0)}</span><div className="bar-track"><div className="bar-stack" style={{ height: `${Math.max(3, categories.reduce((n, c) => n + d[c], 0) / dailyMax * 100)}%` }}>{categories.map(c => <span key={c} style={{ background: colors[c], flex: d[c] }} />)}</div></div><span>{dateLabel(d.date + 'T00:00:00Z')}</span></div>) : <div className="empty-inline">{loading ? 'Loading observation activity…' : 'No activity in this date range.'}</div>}</div></section>}
      {view !== 'map' && <section className="panel reports-panel"><div className="panel-heading"><div><h2>Inspection reports <span className="count-tag">{number(data?.page.total)}</span></h2><p>Image-level findings and recommended next steps</p></div><label className="table-search"><Search size={15} /><input aria-label="Search current report page" placeholder="Search this page…" value={search} onChange={e => setSearch(e.target.value)} /></label></div><div className="table-scroll"><table><thead><tr><th>OBSERVATION</th><th>CONDITION</th><th>SEVERITY</th><th>CAPTURED</th><th>LOCATION</th><th><span className="sr-only">Details</span></th></tr></thead><tbody>{reports.map(r => <tr key={reportKey(r)} onClick={() => setSelected(r)}><td><button className="report-link" onClick={() => setSelected(r)}>{r.pole_id || r.report_id || 'Image observation'}</button><span className="row-description">{r.description || 'No description available'}</span></td><td><Badge report={r} /></td><td><span className={`severity ${r.severity?.toLowerCase()}`}>{r.severity === 'NONE' ? 'None' : r.severity === 'HIGH' ? 'High' : r.severity === 'MEDIUM' ? 'Medium' : 'Unknown'}</span></td><td className="date-cell">{dateLabel(r.timestamp, true)}</td><td><span className="location-cell"><MapPin size={13} />{r.zipcode}</span></td><td><ArrowUpRight size={16} /></td></tr>)}</tbody></table></div>{!reports.length && <div className="empty-state"><ClipboardList size={28} /><h3>{loading ? 'Loading inspections' : search ? 'No matches on this page' : 'No observations found'}</h3><p>{loading ? 'Retrieving the latest assessments.' : search ? 'Try another search or move to a different page.' : 'Try another ZIP code or broaden your filters.'}</p></div>}<div className="table-footer"><span>{data?.page.total ? `${offset + 1}–${Math.min(offset + 10, data.page.total)} of ${data.page.total} observations` : '0 observations'}{search && ' · Search applies to this page'}</span><div><button className="pagination-button" aria-label="Previous report page" disabled={loading || offset === 0} onClick={() => { setOffset(v => Math.max(0, v - 10)); setSearch('') }}><ChevronLeft size={15} /></button><span>Page {Math.floor(offset / 10) + 1}</span><button className="pagination-button" aria-label="Next report page" disabled={loading || data?.page.next_offset == null} onClick={() => { if (data?.page.next_offset != null) setOffset(data.page.next_offset); setSearch('') }}><ChevronRight size={15} /></button></div></div></section>}
      </div><footer className="page-footer"><span><ShieldCheck size={14} /> Preliminary visual assessments. Qualified inspection recommended.</span><span>GridGuardian · Puerto Rico</span></footer>
      </main></div>
      {selected && <div className="drawer-backdrop" onClick={() => setSelected(null)}><aside className="detail-drawer" aria-label="Inspection details" role="dialog" aria-modal="true" onClick={e => e.stopPropagation()} onKeyDown={e => { if (e.key === 'Escape') setSelected(null) }}><button autoFocus className="drawer-close" aria-label="Close inspection details" onClick={() => setSelected(null)}><X size={20} /></button><span className="eyebrow">INSPECTION DETAILS</span><h2>{selected.pole_id || 'Image observation'}</h2><Badge report={selected} /><InspectionImage key={reportKey(selected)} report={selected} /><div className="detail-meta"><span><MapPin size={15} />ZIP {selected.zipcode}</span><span><CalendarDays size={15} />{dateLabel(selected.timestamp, true)}</span></div><div className="detail-section"><h3>Visual assessment</h3><p>{selected.description || 'No assessment description available.'}</p></div><div className="detail-section"><h3>Detected issues</h3>{selected.issues_detected?.length ? <ul>{selected.issues_detected.map((issue, i) => <li key={i}>{issue}</li>)}</ul> : <p>No visible issues reported.</p>}</div><div className="recommendation"><span><Check size={17} />Recommended action</span><p>{selected.recommended_action || 'No action specified.'}</p></div><dl className="detail-ids"><dt>Report ID</dt><dd>{selected.report_id || '—'}</dd><dt>Flight ID</dt><dd>{selected.flight_id || 'Not provided'}</dd><dt>Severity</dt><dd>{selected.severity}</dd><dt>Coordinates</dt><dd>{selected.location ? `${selected.location.latitude}, ${selected.location.longitude}` : 'No GPS coordinates'}</dd></dl>{selected.location && <button className="button primary full-width" onClick={() => { setFocused(selected); setView('map'); setSelected(null) }}>Locate on map <ArrowRight size={16} /></button>}</aside></div>}
      {help && <div className="modal-backdrop" onClick={() => setHelp(false)}><section className="help-modal" role="dialog" aria-modal="true" aria-label="Dashboard guide" onClick={e => e.stopPropagation()} onKeyDown={e => { if (e.key === 'Escape') setHelp(false) }}><button autoFocus className="drawer-close" aria-label="Close dashboard guide" onClick={() => setHelp(false)}><X size={20} /></button><span className="eyebrow">YOUR WORKSPACE</span><h2>A clearer view of the grid.</h2><p>Choose a Puerto Rico ZIP code and apply filters to update the entire dashboard.</p><h3>Explore the map</h3><p>Pan and zoom, switch map styles, or fit observations using the crosshair. Select a marker to read its assessment. Reports without GPS remain in analytics.</p><h3>Understand the numbers</h3><p>Counts represent image observations, not unique poles. Healthy percentage excludes unassessed images. Needs attention includes maintenance and damaged observations. Dates are filtered in UTC.</p><h3>Review and export</h3><p>Open an inspection row for findings and recommendations. Export downloads every report matching the applied filters as CSV, across all pages.</p><button className="button primary" onClick={() => setHelp(false)}>Got it <ArrowRight size={16} /></button></section></div>}
  </div>
}
export default App
