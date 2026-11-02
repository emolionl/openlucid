# Website (Hugo)

The project website, a plain static Hugo site with no external theme. Live at <https://openlucid.nl> (also reachable at <https://openlucid.web.app>).

The journey (`../docs/journey`) and the video scripts (`../promotion/video-scripts`) are mounted into the site by `hugo.toml`, so they are written once and read well both on GitHub and on the website. Links between Markdown files are turned into website links by `layouts/_default/_markup/render-link.html`.

## Preview

```bash
hugo server
```

Then open <http://localhost:1313>.

## Publish

Hosting is the Firebase project `openlucid`:

```bash
hugo --minify
firebase deploy --only hosting
```
