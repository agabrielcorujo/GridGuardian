import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { LocateFixed, Maximize2, MapPin } from 'lucide-react'
import { categoryOf, colors, labels, reportKey } from '../api'
import type { GeoData, Report } from '../api'
const island: L.LatLngBoundsExpression = [[17.85, -67.35], [18.58, -65.2]]
export default function InspectionMap({ data, selected, onSelect }: { data: GeoData | null; selected: Report | null; onSelect: (r: Report) => void }) {
  const host = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const markers = useRef<L.LayerGroup | null>(null)
  const [tileError, setTileError] = useState(false)
  const [layer, setLayer] = useState('light')
  const tile = useRef<L.TileLayer | null>(null)
  useEffect(() => {
    if (!host.current) return
    const instance = L.map(host.current, { zoomControl: false, minZoom: 7, maxZoom: 19 }).fitBounds(island)
    L.control.zoom({ position: 'bottomright' }).addTo(instance)
    map.current = instance
    markers.current = L.layerGroup().addTo(instance)
    const observer = new ResizeObserver(() => instance.invalidateSize())
    observer.observe(host.current)
    return () => { observer.disconnect(); instance.remove(); map.current = null }
  }, [])
  useEffect(() => {
    if (!map.current) return
    tile.current?.remove()
    setTileError(false)
    tile.current = L.tileLayer(layer === 'light' ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}' : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
      attribution: 'Tiles &copy; <a href="https://www.esri.com/">Esri</a> &mdash; ' + (layer === 'light' ? 'Esri, HERE, Garmin, &copy; OpenStreetMap contributors, GIS user community' : 'Esri, Maxar, Earthstar Geographics, GIS user community'), maxNativeZoom: layer === 'light' ? 16 : 19, maxZoom: 19,
    }).on('tileerror', () => setTileError(true)).addTo(map.current)
  }, [layer])
  useEffect(() => {
    markers.current?.clearLayers()
    data?.features.forEach(feature => {
      const report = feature.properties
      const [lon, lat] = feature.geometry.coordinates
      const active = selected && reportKey(selected) === reportKey(report)
      const marker = L.circleMarker([lat, lon], { radius: active ? 11 : 7, color: active ? '#142c32' : '#ffffff', weight: active ? 3 : 2, fillColor: colors[categoryOf(report)], fillOpacity: 0.95 })
      const tooltip = document.createElement('span')
      tooltip.textContent = `${report.pole_id || 'Observation'} · ${labels[categoryOf(report)]}`
      marker.bindTooltip(tooltip, { direction: 'top' }).on('click', () => onSelect(report))
      markers.current?.addLayer(marker)
      const element = marker.getElement()
      if (element) {
        element.setAttribute('tabindex', '0')
        element.setAttribute('role', 'button')
        element.setAttribute('aria-label', tooltip.textContent || 'Open inspection')
        element.addEventListener('keydown', event => {
          if (event instanceof KeyboardEvent && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onSelect(report) }
        })
      }
    })
  }, [data, selected, onSelect])
  useEffect(() => {
    const feature = data?.features.find(f => selected && reportKey(f.properties) === reportKey(selected))
    if (feature) map.current?.flyTo([feature.geometry.coordinates[1], feature.geometry.coordinates[0]], 16, { duration: 0.7 })
  }, [selected, data])
  const fitPoints = () => {
    if (data?.features.length) map.current?.fitBounds(L.latLngBounds(data.features.map(f => [f.geometry.coordinates[1], f.geometry.coordinates[0]])), { padding: [65, 65], maxZoom: 16 })
  }
  return <div className="map-wrap">
    <div ref={host} className="map-canvas" aria-label="Interactive inspection map of Puerto Rico" />
    <div className="map-toolbar"><span className="map-region"><MapPin size={14} /> Puerto Rico</span><div className="map-actions"><button onClick={() => map.current?.fitBounds(island)} title="Show all Puerto Rico" aria-label="Show all Puerto Rico"><Maximize2 size={16} /></button><button onClick={fitPoints} disabled={!data?.features.length} title="Zoom to observations" aria-label="Zoom to observations"><LocateFixed size={16} /></button><select aria-label="Map style" value={layer} onChange={e => setLayer(e.target.value)}><option value="light">Light map</option><option value="satellite">Satellite</option></select></div></div>
    {tileError && <div className="map-notice">Map tiles unavailable. Check your connection or switch map style.</div>}
    {data && !data.features.length && <div className="map-empty">No geolocated observations for these filters.</div>}
    <div className="map-legend">{Object.entries(labels).map(([key, text]) => <span key={key}><i style={{ background: colors[key as keyof typeof colors] }} />{text}</span>)}</div>
  </div>
}
