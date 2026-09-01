import { randomUUID } from "node:crypto";
import { chmod, mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export const name = "dsh-desktop-request-inspector";
export const inject = ["llm", "sessions", "systemPrompt"];

const CACHE_VERSION = 2;
const EMPTY_STATE = Object.freeze({ version: CACHE_VERSION, updatedAt: 0, requests: [] });

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.trunc(parsed)));
}

function jsonSafe(value, key = "", seen = new WeakSet()) {
  if (key === "signal" || key === "replayState") return undefined;
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : String(value);
  if (typeof value === "bigint") return value.toString();
  if (typeof value === "undefined" || typeof value === "function" || typeof value === "symbol") return undefined;
  if (typeof value !== "object") return String(value);
  if (seen.has(value)) return "[Circular]";
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      return value.map((item) => jsonSafe(item, "", seen)).filter((item) => item !== undefined);
    }
    const result = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      const cleaned = jsonSafe(childValue, childKey, seen);
      if (cleaned !== undefined) result[childKey] = cleaned;
    }
    return result;
  } finally {
    seen.delete(value);
  }
}

function latestOrdinaryStep(session) {
  if (!session || !Array.isArray(session.events)) return {};
  for (let index = session.events.length - 1; index >= 0; index -= 1) {
    const event = session.events[index];
    if (event?.type !== "step/start") continue;
    const turn = Number(event.data?.turn);
    const step = Number(event.data?.step);
    return {
      ...(Number.isInteger(turn) ? { turn } : {}),
      ...(Number.isInteger(step) ? { step } : {}),
    };
  }
  return {};
}

function renderSectionText(text, variables) {
  if (typeof text !== "string") return "";
  return text.replace(/\{\{([a-z][a-z0-9_]*)\}\}/g, (match, variable) => {
    if (!Object.hasOwn(variables, variable) || variables[variable] === undefined) return match;
    return String(variables[variable]);
  });
}

function renderPromptAssembly(assembly) {
  const variables = assembly?.variables && typeof assembly.variables === "object" ? assembly.variables : {};
  const sections = Array.isArray(assembly?.sections)
    ? assembly.sections.map((section) => ({
        name: typeof section?.name === "string" ? section.name : "unknown",
        text: renderSectionText(section?.text, variables),
      })).filter((section) => section.text.length > 0)
    : [];
  return { sections };
}

function latestSkillCatalog(messages) {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message?.source?.kind !== "skill-catalog") continue;
    return jsonSafe({
      source: message.source,
      content: message.content,
    });
  }
  return null;
}

function isFixedInstruction(message) {
  const source = message?.source;
  if (message?.role === "system") return true;
  if (source?.kind === "agent-instructions" || source?.kind === "skill-invocation") return true;
  return source?.kind === "plugin" && source?.plugin === "agent-instructions";
}

function fixedInstructions(messages) {
  return messages.filter(isFixedInstruction).map((message) => jsonSafe({
    id: message.id,
    role: message.role,
    source: message.source,
    content: message.content,
  }));
}

async function readState(outputPath) {
  try {
    const parsed = JSON.parse(await readFile(outputPath, "utf8"));
    if (parsed?.version === CACHE_VERSION && Array.isArray(parsed.requests)) return parsed;
  } catch (error) {
    if (error?.code !== "ENOENT") console.warn("dsh desktop inspector: ignoring unreadable cache", error);
  }
  return { ...EMPTY_STATE, requests: [] };
}

async function atomicWrite(outputPath, state, maxBytes) {
  await mkdir(dirname(outputPath), { recursive: true, mode: 0o700 });
  let serialized = JSON.stringify(state, null, 2) + "\n";
  while (Buffer.byteLength(serialized, "utf8") > maxBytes && state.requests.length > 1) {
    state.requests.shift();
    serialized = JSON.stringify(state, null, 2) + "\n";
  }
  const temporaryPath = `${outputPath}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, serialized, { encoding: "utf8", mode: 0o600 });
    await rename(temporaryPath, outputPath);
    await chmod(outputPath, 0o600);
  } catch (error) {
    await unlink(temporaryPath).catch(() => {});
    throw error;
  }
}

export function apply(ctx, rawConfig = {}) {
  const outputPath = typeof rawConfig.outputPath === "string" ? rawConfig.outputPath.trim() : "";
  if (!outputPath) throw new Error("dsh desktop inspector requires config.outputPath");

  const maxRequests = boundedInteger(rawConfig.maxRequests, 32, 1, 100);
  const maxBytes = boundedInteger(rawConfig.maxBytes, 48 * 1024 * 1024, 1024 * 1024, 256 * 1024 * 1024);
  const ordinalBySession = new Map();
  const assemblyBySession = new Map();
  const statePromise = readState(outputPath);
  let writeTail = Promise.resolve();
  let disposed = false;

  ctx.on("system-prompt/assemble", async (_assembly, context, next) => {
    const transformed = await next();
    const sessionId = context?.agent?.session?.id;
    if (!disposed && sessionId !== undefined) {
      assemblyBySession.set(String(sessionId), renderPromptAssembly(transformed));
    }
    return transformed;
  }, { global: true, prepend: true });

  ctx.on("llm/stream", (options, next) => {
    const purpose = typeof options?.purpose === "string" ? options.purpose : "assistant";
    if (!disposed && purpose === "assistant" && options?.sessionId !== undefined) {
      const sessionId = String(options.sessionId);
      const session = ctx.sessions.get(options.sessionId);
      const ordinal = (ordinalBySession.get(sessionId) ?? 0) + 1;
      ordinalBySession.set(sessionId, ordinal);
      const position = latestOrdinaryStep(session);
      const capturedAt = Date.now();
      const messages = Array.isArray(options.messages) ? options.messages : [];
      const system = typeof options.system === "string" ? options.system : "";
      const promptAssembly = assemblyBySession.get(sessionId) ?? { sections: [] };
      const assembledSystem = promptAssembly.sections.map((section) => section.text).join("\n\n");
      const record = {
        id: randomUUID(),
        capturedAt,
        sessionId,
        ordinal,
        purpose,
        ...position,
        cwd: typeof session?.header?.cwd === "string" ? session.header.cwd : null,
        route: jsonSafe({
          provider: options.provider,
          model: options.model,
          reasoningEffort: options.reasoningEffort,
        }),
        system,
        promptAssembly: {
          ...promptAssembly,
          matchesFinal: assembledSystem === system,
        },
        tools: jsonSafe(Array.isArray(options.tools) ? options.tools : []),
        skillCatalog: latestSkillCatalog(messages),
        fixedInstructions: fixedInstructions(messages),
      };

      writeTail = writeTail.then(async () => {
        const state = await statePromise;
        const attempt = state.requests.filter((item) =>
          item.sessionId === sessionId && item.turn === record.turn && item.step === record.step
        ).length + 1;
        state.requests.push({ ...record, attempt });
        if (state.requests.length > maxRequests) {
          state.requests.splice(0, state.requests.length - maxRequests);
        }
        state.updatedAt = capturedAt;
        await atomicWrite(outputPath, state, maxBytes);
      }).catch((error) => {
        console.warn("dsh desktop inspector: capture failed", error);
      });
    }
    return next();
  }, { global: true, prepend: true });

  ctx.effect(() => async () => {
    disposed = true;
    assemblyBySession.clear();
    await writeTail;
    await unlink(outputPath).catch((error) => {
      if (error?.code !== "ENOENT") console.warn("dsh desktop inspector: cache cleanup failed", error);
    });
  });
}
