#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const http = require("node:http");
const https = require("node:https");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { TextDecoder } = require("node:util");

const BRIDGE_URL = process.env.CLAUDEBOX_CLIPBOARD_URL || "";
const TOKEN = process.env.CLAUDEBOX_CLIPBOARD_TOKEN || "";
const TIMEOUT_MS = Math.max(1, parseInt(process.env.CLAUDEBOX_CLIPBOARD_TIMEOUT_MS || "7000", 10));
const MAX_BYTES = Math.max(1, parseInt(process.env.CLAUDEBOX_CLIPBOARD_MAX_BYTES || String(20 * 1024 * 1024), 10));

function commandName() {
  return path.basename(process.argv[1] || "");
}

function args() {
  return process.argv.slice(2);
}

function parseAllowed(allowedValueFlags, allowedBooleanFlags) {
  const parsed = { ok: true, values: {}, booleans: new Set(), positionals: [] };
  const valueFlags = new Set(allowedValueFlags);
  const booleanFlags = new Set(allowedBooleanFlags);
  const argv = args();

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--") {
      parsed.ok = false;
      return parsed;
    }
    if (!arg.startsWith("-")) {
      parsed.positionals.push(arg);
      continue;
    }
    const eq = arg.indexOf("=");
    if (eq !== -1) {
      const key = arg.slice(0, eq);
      const value = arg.slice(eq + 1);
      if (!valueFlags.has(key) || value === "") {
        parsed.ok = false;
        return parsed;
      }
      parsed.values[key] = value;
      continue;
    }
    if (valueFlags.has(arg)) {
      if (i + 1 >= argv.length || argv[i + 1].startsWith("-")) {
        parsed.ok = false;
        return parsed;
      }
      parsed.values[arg] = argv[i + 1];
      i += 1;
      continue;
    }
    if (booleanFlags.has(arg)) {
      parsed.booleans.add(arg);
      continue;
    }
    parsed.ok = false;
    return parsed;
  }

  if (parsed.positionals.length > 0) parsed.ok = false;
  return parsed;
}

function parsedValue(parsed, names) {
  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(parsed.values, name)) {
      return parsed.values[name];
    }
  }
  return null;
}

function parsedHas(parsed, names) {
  return names.some((name) => parsed.booleans.has(name));
}

function clipboardSelectionOnly(selection) {
  return selection === null || selection === "clipboard";
}

function classifyRequest() {
  const cmd = commandName();
  if (cmd === "xclip") {
    const parsed = parseAllowed(["-selection", "-t", "-target"], ["-o", "-out", "-i", "-in"]);
    if (!parsed.ok || !clipboardSelectionOnly(parsedValue(parsed, ["-selection"]))) return null;
    if (!parsedHas(parsed, ["-o", "-out"])) {
      const target = parsedValue(parsed, ["-t", "-target"]) || "text/plain";
      if (isTextType(target)) return { endpoint: "/text", kind: "text", method: "POST" };
      return null;
    }
    const target = parsedValue(parsed, ["-t", "-target"]) || "text/plain";
    if (target === "TARGETS") return { endpoint: "/types", kind: "types", method: "GET" };
    if (target === "image/png") return { endpoint: "/image", kind: "image", method: "GET" };
    return null;
  }

  if (cmd === "xsel") {
    const parsed = parseAllowed(["-t", "--type"], ["-b", "--clipboard", "-i", "--input", "-o", "--output"]);
    if (!parsed.ok || !parsedHas(parsed, ["-b", "--clipboard"])) return null;
    if (parsedHas(parsed, ["-o", "--output"])) return null;
    if (!parsedHas(parsed, ["-i", "--input"])) return null;
    const target = parsedValue(parsed, ["-t", "--type"]) || "text/plain";
    if (isTextType(target)) return { endpoint: "/text", kind: "text", method: "POST" };
    return null;
  }

  if (cmd === "wl-paste") {
    const parsed = parseAllowed(["-t", "--type"], ["-l", "--list-types"]);
    if (!parsed.ok) return null;
    if (parsedHas(parsed, ["-l", "--list-types"])) return { endpoint: "/types", kind: "types", method: "GET" };
    const target = parsedValue(parsed, ["-t", "--type"]) || "text/plain";
    if (target === "image/png") return { endpoint: "/image", kind: "image", method: "GET" };
    return null;
  }

  if (cmd === "wl-copy") {
    const parsed = parseAllowed(["-t", "--type"], []);
    if (!parsed.ok) return null;
    const target = parsedValue(parsed, ["-t", "--type"]) || "text/plain";
    if (isTextType(target)) return { endpoint: "/text", kind: "text", method: "POST" };
    return null;
  }

  return null;
}

function isTextType(target) {
  return target === "text/plain" || target === "UTF8_STRING" || target === "text/plain;charset=utf-8";
}

function currentRealPath() {
  try {
    return fs.realpathSync(process.argv[1]);
  } catch (_error) {
    return "";
  }
}

function findDelegate(cmd) {
  const current = currentRealPath();
  const pathEntries = (process.env.PATH || "").split(path.delimiter).filter(Boolean);
  for (const entry of pathEntries) {
    const candidate = path.join(entry, cmd);
    try {
      const stat = fs.statSync(candidate);
      if (!stat.isFile()) continue;
      const real = fs.realpathSync(candidate);
      if (real === current) continue;
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch (_error) {
      continue;
    }
  }
  return null;
}

function delegateOrFail() {
  const delegate = findDelegate(commandName());
  if (!delegate) process.exit(1);

  const child = spawn(delegate, args(), { stdio: "inherit" });
  child.on("exit", (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    process.exit(code === null ? 1 : code);
  });
  child.on("error", () => process.exit(1));
}

function bridgeEnabled() {
  return BRIDGE_URL && TOKEN;
}

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let received = 0;
    process.stdin.on("data", (chunk) => {
      received += chunk.length;
      if (received > MAX_BYTES) {
        reject(new Error("stdin too large"));
        process.stdin.destroy();
        return;
      }
      chunks.push(chunk);
    });
    process.stdin.on("end", () => resolve(Buffer.concat(chunks)));
    process.stdin.on("error", reject);
  });
}

function decodeUtf8(buffer) {
  return new TextDecoder("utf-8", { fatal: true }).decode(buffer);
}

function requestBridge(endpoint, method, body) {
  return new Promise((resolve, reject) => {
    let url;
    try {
      url = new URL(endpoint, BRIDGE_URL);
    } catch (error) {
      reject(error);
      return;
    }

    const transport = url.protocol === "https:" ? https : http;
    const req = transport.request(
      url,
      {
        method,
        headers: {
          Authorization: "Bearer " + TOKEN,
          ...(body !== undefined ? {
            "Content-Type": "text/plain; charset=utf-8",
            "Content-Length": String(body.length),
          } : {}),
        },
        timeout: TIMEOUT_MS,
      },
      (res) => {
        const chunks = [];
        let received = 0;
        res.on("data", (chunk) => {
          received += chunk.length;
          if (received > MAX_BYTES) {
            req.destroy(new Error("bridge response too large"));
            return;
          }
          chunks.push(chunk);
        });
        res.on("end", () => {
          const body = Buffer.concat(chunks);
          if (res.statusCode === 200 || res.statusCode === 204) {
            resolve({ statusCode: res.statusCode, body });
          } else {
            reject(new Error("bridge status " + res.statusCode));
          }
        });
      },
    );

    req.on("timeout", () => {
      req.destroy(new Error("bridge timeout"));
    });
    req.on("error", reject);
    req.end(body);
  });
}

async function main() {
  const request = classifyRequest();
  if (!request) {
    if (bridgeEnabled()) process.exit(1);
    delegateOrFail();
    return;
  }

  if (!bridgeEnabled()) {
    delegateOrFail();
    return;
  }

  try {
    let body;
    if (request.kind === "text") {
      body = await readStdin();
      decodeUtf8(body);
    }

    const response = await requestBridge(request.endpoint, request.method, body);
    if (request.kind === "types") {
      const payload = JSON.parse(response.body.toString("utf-8"));
      const types = Array.isArray(payload.types) ? payload.types : [];
      if (!types.includes("image/png")) process.exit(1);
      process.stdout.write("image/png\n");
      return;
    }

    if (request.kind === "text") return;

    if (response.body.length === 0) process.exit(1);
    process.stdout.write(response.body);
  } catch (_error) {
    process.exit(1);
  }
}

main();
