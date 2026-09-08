import { readFileSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { ProjectMemory } from "./memory.mjs";
export const name = "dsh-desktop-project-memory";
export const inject = [
  "webServer",
  "workspaceRegistry",
  "agents",
  "tools",
  "loader",
];
export function apply(ctx, config) {
  if (typeof config.token !== "string" || config.token.length < 32)
    throw new Error("项目记忆启动配置不完整。");
  const memory = new ProjectMemory(ctx);
  const source = readFileSync(
    new URL("./client.js", import.meta.url),
    "utf8",
  ).replace('/* PROJECT_MEMORY_CSS */ ""', () =>
    JSON.stringify(
      readFileSync(new URL("./style.css", import.meta.url), "utf8"),
    ),
  );
  ctx.effect(() =>
    ctx.webServer.register({
      kind: "exact",
      path: "/dsh-desktop/project-memory.js",
      handler: (_req, res) => {
        res.writeHead(200, {
          "Content-Type": "text/javascript; charset=utf-8",
          "Cache-Control": "no-store",
        });
        res.end(source);
      },
    }),
  );
  ctx.effect(() =>
    ctx.webServer.tapIndex((html) =>
      html.replace(
        "</head>",
        `<script>
    if(globalThis.__DSH_BOOT__?.entries&&window.webkit?.messageHandlers.dshProjectMemory){
      globalThis.__DSH_BOOT__.entries.push({id:'dsh-desktop-project-memory',url:'/dsh-desktop/project-memory.js',rev:'1',inject:['@deepseek-ai/dsh-client-runtime'],immediately:true});
    }</script></head>`,
      ),
    ),
  );
  const reply = (res, status, value) => {
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    });
    res.end(JSON.stringify(value));
  };
  ctx.effect(() =>
    ctx.webServer.register({
      kind: "exact",
      path: "/dsh-desktop/project-memory/v1",
      handler: async (req, res) => {
        const given = Buffer.from(req.headers.authorization ?? ""),
          expected = Buffer.from("Bearer " + config.token);
        if (
          req.method !== "POST" ||
          req.headers.origin ||
          given.length !== expected.length ||
          !timingSafeEqual(given, expected)
        )
          return reply(res, 403, { error: "此入口仅供本机客户端使用。" });
        try {
          let size = 0;
          const parts = [];
          for await (const p of req) {
            size += p.length;
            if (size > 200000) throw new Error("请求过大。");
            parts.push(p);
          }
          const input = JSON.parse(Buffer.concat(parts));
          const workspace = ctx.workspaceRegistry
            .list()
            .find((w) => w.id === input.workspaceID);
          if (!workspace) throw new Error("项目已移除或尚未加载。");
          // Project identity is server-resolved. A client-supplied path is never used.
          const value =
            input.action === "snapshot"
              ? await memory.read(workspace)
              : input.action === "mutate"
                ? await memory.mutate(workspace, input.input ?? {})
                : undefined;
          if (!value) throw new Error("未知的项目记忆操作。");
          reply(res, 200, { value });
        } catch (e) {
          reply(res, e.name === "Conflict" ? 409 : 400, { error: e.message });
        }
      },
    }),
  );
}
