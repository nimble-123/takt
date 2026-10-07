# Takt – Produktseite

Statische One-Page-Seite für GitHub Pages: Vite, GSAP (ScrollTrigger, SplitText), Lenis, three.js und Motion. Schriften (Bricolage Grotesque, JetBrains Mono) sind selbst gehostet, es gibt keine Tracker und keine externen Anfragen.

```bash
npm ci
npm run dev      # http://localhost:5173/takt/
npm run build    # nach dist/
```

- `src/particles.js` – WebGL-Partikelfeld mit fünf Formationen (Logo, Ziffernblatt, Timeline, Wochenbalken, Buchung)
- `src/main.js` – Seitenaufbau, Scroll-Szenen, Mikrointeraktionen
- `src/i18n.js` – Texte Englisch und Deutsch (`?lang=de`)
- Screenshots kommen direkt aus `docs/assets/screenshots`, die Version aus `project.yml`.

`prefers-reduced-motion` schaltet Lenis, Pinning und Partikelbewegung ab; alle Inhalte stehen dann statisch untereinander.
