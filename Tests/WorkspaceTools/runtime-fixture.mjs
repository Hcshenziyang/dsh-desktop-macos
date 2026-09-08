// Used only by isolated integration tests. No remote provider is ever contacted.
import { createRequire } from "node:module";
import { realpathSync } from "node:fs";
import { randomUUID } from "node:crypto";
const require = createRequire(realpathSync(process.argv[1]));
const { LlmAdapter } = await import(require.resolve("@deepseek-ai/dsh-llm"));
const { assembleContextFor } = await import(
  require.resolve("@deepseek-ai/dsh-agent")
);
export const inject = [
  "webServer",
  "agents",
  "agentPresets",
  "workspaceRegistry",
  "llm",
  "tools",
  "systemPrompt",
];
export function apply(ctx, config) {
  const requests = [];
  class Fixture extends LlmAdapter {
    async *stream(options) {
      requests.push({
        sessionID: options.sessionId,
        provider: options.provider,
        system: options.system,
        messages: options.messages,
      });
      const block = { type: "text", text: "测试模型已读取工作区待办与便签。" };
      yield { type: "block-start", index: 0, blockType: "text" };
      yield { type: "text-delta", index: 0, text: block.text };
      yield { type: "block-end", index: 0, block };
      yield { type: "usage", usage: { inputTokens: 1, outputTokens: 1 } };
      yield { type: "finish", reason: { kind: "stop" } };
    }
  }
  ctx.effect(() => ctx.llm.registerAdapter(["workspace-test"], new Fixture()));
  const handles = [];
  ctx.effect(() => () => Promise.all(handles.map((h) => h.dispose())));
  ctx.effect(() =>
    ctx.webServer.register({
      kind: "exact",
      path: "/workspace-tools-test",
      handler: async (req, res) => {
        if (req.headers.authorization !== "Bearer " + config.token) {
          res.writeHead(403);
          res.end();
          return;
        }
        try {
          const parts = [];
          for await (const p of req) parts.push(p);
          const input = JSON.parse(Buffer.concat(parts));
          let value;
          if (input.action === "create") {
            const w = await ctx.workspaceRegistry.create(
              input.path,
              input.title,
            );
            const handle = await ctx.agents.create({
              sessionId: "workspace-test-" + randomUUID(),
              meta: { cwd: w.path, agentPreset: "standard" },
              agentOptions: { provider: "workspace-test", model: "fixture" },
              setup: async (scope) => {
                await ctx.agentPresets.mount(scope, "standard");
              },
            });
            handles.push(handle);
            await w.attachSession(handle.agent.id);
            value = { workspaceID: w.id, sessionID: handle.agent.id };
          } else if (input.action === "invoke")
            value = await ctx.tools.execute({
              name: input.name,
              arguments: input.arguments,
              agent: ctx.agents.get(input.sessionID),
              callId: randomUUID(),
              signal: new AbortController().signal,
            });
          else if (input.action === "context")
            value = await ctx.systemPrompt.assemble(
              assembleContextFor(ctx.agents.get(input.sessionID)),
            );
          else if (input.action === "requests") value = requests;
          else if (input.action === "turn") {
            const agent = ctx.agents.get(input.sessionID);
            agent.followup({
              id: randomUUID(),
              role: "user",
              source: { kind: "user" },
              content: [{ type: "text", text: "查看我的工作区待办和便签。" }],
            });
            await agent.whenIdle();
            value = agent.session.events.filter((e) => e.type === "turn/end");
          } else throw new Error("Unknown test action");
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(value));
        } catch (error) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: error.message }));
        }
      },
    }),
  );
}
