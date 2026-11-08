# GridGuardian dashboard

React + TypeScript + Vite dashboard for visual inspections of Puerto Rico's
electrical infrastructure. Uses live API data, Leaflet maps, and no authentication.

## Run locally

```sh
npm ci
cp .env.example .env.local
npm run dev
```

Open the Local URL printed by Vite (normally http://localhost:5173).
`.env.local` is already configured in this working checkout. The tracked
`.env.example` documents `VITE_API_BASE_URL`; replace it in `.env.local` to
change backends, then restart Vite. This is a public browser configuration
value, not a place for credentials. Production builds read the variable at
build time.

```sh
npm run build
npm run preview
```

## Features

- ZIP-scoped overview, map, and inspection views. Defaults to `00901`.
- Shared classification, severity, inclusive UTC date range, flight, and pole filters.
- Live analytics for total/assessable images, healthy percentage, attention needs,
  location coverage, classification distribution, and daily activity.
- Interactive Puerto Rico map: pan, zoom, light/satellite styles, reset to island,
  fit observations, marker tooltips, and inspection details. Missing GPS is never
  replaced with invented coordinates.
- Paginated reports, search within the current page, detailed findings and
  recommended actions, and locate-on-map interaction.
- CSV export of all matching report pages, with spreadsheet formula escaping.
- Loading, retryable API errors, empty states, responsive layout, reduced-motion
  support, and keyboard-accessible controls.

The dashboard calls `GET /analytics/{zipcode}`, `/map/{zipcode}`, and
`/reports/{zipcode}` directly. The API must allow CORS from the local origin.
Requests are canceled when filters change. Map tiles use Esri’s public light-gray and imagery raster services, verified
without API keys. Both require network access and retain source attribution. Counts are
image observations, not unique pole inventory. The API currently scopes data
by ZIP, so an island-wide aggregate cannot be requested from this UI.

Clicking a map marker or inspection row opens its original S3 image alongside
findings. The panel requests `/reports/{zipcode}/image?sort_key=...` on demand,
then displays the returned five-minute signed URL. Loading, missing-image,
failed-load and retry states are included; “Open original” opens the full image.
Closing or changing observations cancels the in-flight URL request. The API
image endpoint and its S3 read policy must be deployed first. S3 stays private;
AWS credentials are never sent to the browser.

Environment files, node_modules, builds, logs, TypeScript caches, and browser
verification artifacts are gitignored. Commit package-lock.json for repeatable
installs. No deployment or publishing is performed by this project setup.


## Vercel deployment

Import `agabrielcorujo/GridGuardian` from GitHub and use `main` as the production
branch. Set the project root directory to `src/GridGuardianUI/GridGuardianUI`.
The checked-in `vercel.json` configures Vite, `npm ci`, `npm run build`, and
`dist`; package.json selects Node 22.x.

Set `VITE_API_BASE_URL` for Production and Preview to the URL documented in
`.env.example`. Environment changes require a new build. Do not upload local
environment files or AWS credentials. The API remains hosted on AWS Lambda;
image links are issued by the API, so Vercel needs no S3 credentials.

After deployment verify ZIP 00901 analytics, map tiles and markers, an image
preview, report pagination, and CSV export. Production pushes to `main` should
redeploy automatically once the Vercel GitHub integration is connected.
