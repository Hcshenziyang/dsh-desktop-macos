import { readFileSync } from "node:fs";

export const name = "dsh-desktop-project-views";
export const inject = ["webServer"];

export function apply(ctx) {
  if (typeof ctx.webServer.tapIndex !== "function") return;
  const css =
    readFileSync(new URL("./project-views.css", import.meta.url), "utf8") +
    "\n" +
    readFileSync(new URL("./markdown-document.css", import.meta.url), "utf8");
  const engine = readFileSync(
    new URL("./vendor/markdown-it.min.js", import.meta.url),
    "utf8",
  );
  const documentTools = readFileSync(
    new URL("./markdown-document.js", import.meta.url),
    "utf8",
  );
  const source = readFileSync(
    new URL("./project-views-client.js", import.meta.url),
    "utf8",
  )
    .replace('/* PROJECT_VIEWS_CSS */ ""', () => JSON.stringify(css))
    .replace(
      "/* MARKDOWN_ENGINE */ null",
      () =>
        `(()=>{const module={exports:{}};const exports=module.exports;\n${engine}\nreturn module.exports;})()`,
    )
    .replace("/* MARKDOWN_TOOLS */ null", () =>
      documentTools.trim().replace(/;$/, ""),
    );
  ctx.effect(() =>
    ctx.webServer.register({
      kind: "exact",
      path: "/dsh-desktop/project-views.js",
      handler(_req, res) {
        res.writeHead(200, {
          "Content-Type": "text/javascript; charset=utf-8",
          "Cache-Control": "no-store",
        });
        res.end(source);
      },
    }),
  );
  // Plain browsers and other clients keep the upstream UI. Native file access
  // uses WebKit's private request/reply channel, never an HTTP filesystem route.
  ctx.effect(() =>
    ctx.webServer.tapIndex((html) =>
      html.replace(
        "</head>",
        `<script>
    if (globalThis.__DSH_BOOT__?.entries && window.webkit?.messageHandlers.dshProjectFiles) {
      globalThis.__DSH_BOOT__.entries.push({id:'dsh-desktop-project-views',url:'/dsh-desktop/project-views.js',rev:'1',inject:['@deepseek-ai/dsh-client-runtime'],immediately:true});
    }
  </script></head>`,
      ),
    ),
  );
}
