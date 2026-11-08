import { useEffect, useState } from 'react'
import { ImageOff, LoaderCircle, Maximize2, RefreshCw } from 'lucide-react'
import { requestImage } from '../api'
import type { Report } from '../api'

export default function InspectionImage({ report }: { report: Report }) {
  const [url, setUrl] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    const controller = new AbortController()
    setUrl(''); setError(''); setLoading(true)
    requestImage(report, controller.signal).then(setUrl).catch(e => {
      if (!controller.signal.aborted) { setError(e.message); setLoading(false) }
    })
    return () => controller.abort()
  }, [report, attempt])
  return <figure className="inspection-image">
    {loading && <div className="image-status" role="status"><LoaderCircle size={22} className="spin" /><span>Loading inspection image…</span></div>}
    {error && <div className="image-status" role="status"><ImageOff size={24} /><span>{error}</span><button className="button" onClick={() => setAttempt(v => v + 1)}><RefreshCw size={13} />Retry image</button></div>}
    {url && !error && <><img src={url} alt={`Drone inspection of ${report.pole_id || 'electrical infrastructure'} in ZIP ${report.zipcode}`} onLoad={() => setLoading(false)} onError={() => { setLoading(false); setError('The image could not be loaded. Retry to request a fresh link.') }} style={{ visibility: loading ? 'hidden' : 'visible' }} />{!loading && <a className="image-expand" href={url} target="_blank" rel="noopener noreferrer"><Maximize2 size={13} />Open original</a>}</>}
    <figcaption>Original inspection image</figcaption>
  </figure>
}
