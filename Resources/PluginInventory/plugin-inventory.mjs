import { mkdir, writeFile, rename, unlink } from "node:fs/promises";
import { dirname } from "node:path";

export const name = "dsh-desktop-plugin-inventory";
export const inject = ["loader"];

// Same public projection used by dsh-host-plugin-inventory. Never serialize
// entry configuration, plugin credentials, prompts, or session content.
export function snapshot(loader, pid = process.pid, now = Date.now()) {
  const phases = ["pending", "loading", "active", "failed", null, "unloading"];
  return {
    pid, updatedAt: now,
    entries: Array.from(loader.entries())
      .filter(entry => !entry.options.group)
      .map(entry => ({
        moduleName: entry.options.name,
        enabled: !entry.disabled,
        fiberPhase: entry.fiber ? (phases[entry.fiber.state] ?? null) : null,
      })),
  };
}

export function apply(ctx, config) {
  const output = config.outputPath;
  if (typeof output !== "string" || !output.startsWith("/")) return;
  const temporary = `${output}.${process.pid}.tmp`;
  let disposed = false;
  let writing = false;
  let pending = Promise.resolve();
  const publish = () => {
    if (disposed || writing) return;
    writing = true;
    pending = (async () => {
      const data = JSON.stringify(snapshot(ctx.loader));
      await mkdir(dirname(output), { recursive: true, mode: 0o700 });
      await writeFile(temporary, data, { mode: 0o600 });
      if (!disposed) await rename(temporary, output);
    })().catch(error => {
      console.warn("dsh desktop: plugin inventory unavailable", error.message);
    }).finally(() => { writing = false; });
  };
  const timer = setInterval(publish, 1000);
  timer.unref?.();
  publish();
  ctx.effect(() => async () => {
    disposed = true;
    clearInterval(timer);
    await pending;
    await unlink(temporary).catch(() => {});
    await unlink(output).catch(() => {});
  });
}
