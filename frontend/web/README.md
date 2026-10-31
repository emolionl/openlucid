# Web app (Vue)

The morning side of Lucid: your night's report, the dream journal and your own analysis, in the browser.

## Start it

1. Start the backend first (see `../../backend/README.md`).
2. From this folder:

```bash
npm install
npm run dev
```

3. Open the address it prints (usually <http://localhost:5173>) and press **Wave at the Diary Keeper**.

The backend address defaults to `http://localhost:8000`. To change it, create a file `.env.local` with:

```
VITE_DIARY_KEEPER_URL=http://192.168.1.20:8000
```
