// Copies the static Next.js export into ../html, the folder the resource
// actually ships (fxmanifest ui_page('html/ui.html')). The NUI browser loads
// files straight off disk, so this replaces `next start` — there is no server.
import { existsSync, rmSync } from 'node:fs';
import { cp, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const resourceRoot = path.dirname(projectRoot);
const outDir = path.join(projectRoot, 'out');
const htmlDir = path.join(resourceRoot, 'html');

if (!existsSync(outDir)) {
  console.error('[deploy-to-html] Missing nui/out — run `next build` first.');
  process.exit(1);
}

rmSync(htmlDir, { recursive: true, force: true });
await cp(outDir, htmlDir, { recursive: true });

const exportedIndex = path.join(htmlDir, 'index.html');
const uiEntry = path.join(htmlDir, 'ui.html');
if (existsSync(exportedIndex)) {
  await rename(exportedIndex, uiEntry);
}

// The NUI is a single page with no routing, so Next's auto-generated 404
// page is dead weight — strip it rather than shipping it.
rmSync(path.join(htmlDir, '404.html'), { force: true });
rmSync(path.join(htmlDir, '404'), { recursive: true, force: true });

console.log(`[deploy-to-html] Deployed static export to ${path.relative(resourceRoot, htmlDir)}/`);
