const assert = require("node:assert");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const test = require("node:test");

const ROOT = path.resolve(__dirname, "..");
const CLIENT = path.join(ROOT, "build", "clipboard-client.js");
const PNG_BYTES = Buffer.from("\x89PNG\r\n\x1a\nfixture-png", "binary");

function startClipboardServer(handler) {
  const server = http.createServer(handler);
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      resolve({
        url: `http://127.0.0.1:${address.port}`,
        close: () => new Promise((done) => server.close(done)),
      });
    });
  });
}

function runClient(linkName, args, envOverrides = {}) {
  return runClientWithInput(linkName, args, null, envOverrides);
}

function runClientWithInput(linkName, args, input, envOverrides = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "claudebox-clipboard-client-"));
  const link = path.join(tmp, linkName);
  fs.symlinkSync(CLIENT, link);

  return new Promise((resolve) => {
    const child = spawn(process.execPath, [link, ...args], {
      env: {
        ...process.env,
        CLAUDEBOX_CLIPBOARD_URL: envOverrides.url || "",
        CLAUDEBOX_CLIPBOARD_TOKEN: envOverrides.token || "",
        CLAUDEBOX_CLIPBOARD_TIMEOUT_MS: envOverrides.timeout || "1000",
        CLAUDEBOX_CLIPBOARD_MAX_BYTES: envOverrides.maxBytes || "20971520",
        PATH: envOverrides.path || process.env.PATH,
      },
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    if (input === null) {
      child.stdin.end();
    } else {
      child.stdin.end(input);
    }
    child.on("close", (code) => {
      fs.rmSync(tmp, { recursive: true, force: true });
      resolve({
        code,
        stdout: Buffer.concat(stdout),
        stderr: Buffer.concat(stderr).toString("utf-8"),
      });
    });
  });
}

test("xclip TARGETS returns image/png only when server reports image type", async () => {
  const seen = [];
  const server = await startClipboardServer((req, res) => {
    seen.push({ url: req.url, auth: req.headers.authorization });
    assert.strictEqual(req.url, "/types");
    assert.strictEqual(req.headers.authorization, "Bearer secret-token");
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ types: ["image/png"] }));
  });

  try {
    const result = await runClient("xclip", ["-selection", "clipboard", "-t", "TARGETS", "-o"], {
      url: server.url,
      token: "secret-token",
    });

    assert.strictEqual(result.code, 0);
    assert.strictEqual(result.stdout.toString("utf-8"), "image/png\n");
    assert.strictEqual(seen.length, 1);
  } finally {
    await server.close();
  }
});

test("wl-paste image request streams exact PNG bytes", async () => {
  const server = await startClipboardServer((req, res) => {
    assert.strictEqual(req.url, "/image");
    assert.strictEqual(req.headers.authorization, "Bearer token");
    res.setHeader("Content-Type", "image/png");
    res.end(PNG_BYTES);
  });

  try {
    const result = await runClient("wl-paste", ["--type", "image/png"], {
      url: server.url,
      token: "token",
    });

    assert.strictEqual(result.code, 0);
    assert.deepStrictEqual(result.stdout, PNG_BYTES);
  } finally {
    await server.close();
  }
});

test("server 204 for missing image exits nonzero without stdout", async () => {
  const server = await startClipboardServer((req, res) => {
    assert.strictEqual(req.url, "/image");
    res.writeHead(204);
    res.end();
  });

  try {
    const result = await runClient("xclip", ["-t", "image/png", "-o"], {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(result.stdout.length, 0);
  } finally {
    await server.close();
  }
});

test("unavailable server exits nonzero quickly", async () => {
  const blocker = net.createServer();
  await new Promise((resolve) => blocker.listen(0, "127.0.0.1", resolve));
  const port = blocker.address().port;
  await new Promise((resolve) => blocker.close(resolve));

  const result = await runClient("wl-paste", ["--list-types"], {
    url: `http://127.0.0.1:${port}`,
    token: "token",
    timeout: "200",
  });

  assert.notStrictEqual(result.code, 0);
  assert.strictEqual(result.stdout.length, 0);
});

test("unsupported text requests exit nonzero without contacting the bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClient("wl-paste", [], {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(result.stdout.length, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("Claude wl-copy and xclip text commands post UTF-8 to the bridge", async () => {
  const seen = [];
  const server = await startClipboardServer((req, res) => {
    seen.push({ url: req.url, method: req.method, auth: req.headers.authorization });
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      assert.strictEqual(req.url, "/text");
      assert.strictEqual(req.method, "POST");
      assert.strictEqual(req.headers.authorization, "Bearer token");
      assert.strictEqual(Buffer.concat(chunks).toString("utf-8"), "copy me");
      res.writeHead(204);
      res.end();
    });
  });

  try {
    for (const [command, argv] of [["wl-copy", []], ["xclip", ["-selection", "clipboard"]]]) {
      const result = await runClientWithInput(command, argv, Buffer.from("copy me"), {
        url: server.url,
        token: "token",
      });
      assert.strictEqual(result.code, 0);
      assert.strictEqual(result.stdout.length, 0);
    }
    assert.strictEqual(seen.length, 2);
  } finally {
    await server.close();
  }
});

test("empty text copy still posts a zero-length UTF-8 body", async () => {
  const server = await startClipboardServer((req, res) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      assert.strictEqual(req.headers["content-type"], "text/plain; charset=utf-8");
      assert.strictEqual(req.headers["content-length"], "0");
      assert.strictEqual(Buffer.concat(chunks).length, 0);
      res.writeHead(204);
      res.end();
    });
  });

  try {
    const result = await runClientWithInput("wl-copy", [], Buffer.alloc(0), {
      url: server.url,
      token: "token",
    });

    assert.strictEqual(result.code, 0);
  } finally {
    await server.close();
  }
});

test("xsel clipboard input posts UTF-8 text to the bridge", async () => {
  const server = await startClipboardServer((req, res) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      assert.strictEqual(req.url, "/text");
      assert.strictEqual(Buffer.concat(chunks).toString("utf-8"), "selected text");
      res.writeHead(204);
      res.end();
    });
  });

  try {
    const result = await runClientWithInput("xsel", ["-b", "-i"], Buffer.from("selected text"), {
      url: server.url,
      token: "token",
    });

    assert.strictEqual(result.code, 0);
  } finally {
    await server.close();
  }
});

test("binary image writes fail without contacting the bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClientWithInput("wl-copy", ["--type=image/png"], PNG_BYTES, {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("xclip version request does not contact enabled bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClient("xclip", ["--version"], {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("wl-copy positional text does not contact enabled bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClient("wl-copy", ["literal text"], {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("unknown xsel flags do not contact enabled bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClient("xsel", ["--mystery"], {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("primary selection writes do not contact enabled bridge", async () => {
  let contacts = 0;
  const server = await startClipboardServer((_req, res) => {
    contacts += 1;
    res.writeHead(500);
    res.end();
  });

  try {
    const result = await runClientWithInput("xclip", ["-selection", "primary"], Buffer.from("nope"), {
      url: server.url,
      token: "token",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(contacts, 0);
  } finally {
    await server.close();
  }
});

test("long xsel clipboard input form posts UTF-8 text", async () => {
  const server = await startClipboardServer((req, res) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      assert.strictEqual(req.url, "/text");
      assert.strictEqual(Buffer.concat(chunks).toString("utf-8"), "long form");
      res.writeHead(204);
      res.end();
    });
  });

  try {
    const result = await runClientWithInput("xsel", ["--clipboard", "--input"], Buffer.from("long form"), {
      url: server.url,
      token: "token",
    });

    assert.strictEqual(result.code, 0);
  } finally {
    await server.close();
  }
});

test("disabled bridge delegates to real xclip when present", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "claudebox-real-xclip-"));
  const real = path.join(tmp, "xclip");
  fs.writeFileSync(real, "#!/bin/sh\nprintf delegated\n", { mode: 0o755 });

  try {
    const result = await runClient("xclip", ["-o"], {
      path: tmp,
    });

    assert.strictEqual(result.code, 0);
    assert.strictEqual(result.stdout.toString("utf-8"), "delegated");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("disabled bridge delegates to real xsel when present", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "claudebox-real-xsel-"));
  const real = path.join(tmp, "xsel");
  fs.writeFileSync(real, "#!/bin/sh\nprintf delegated-xsel\n", { mode: 0o755 });

  try {
    const result = await runClient("xsel", ["-b", "-o"], {
      path: tmp,
    });

    assert.strictEqual(result.code, 0);
    assert.strictEqual(result.stdout.toString("utf-8"), "delegated-xsel");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("disabled bridge exits nonzero when no real clipboard command is present", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "claudebox-empty-path-"));

  try {
    const result = await runClient("wl-paste", ["--list-types"], {
      path: tmp,
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(result.stdout.length, 0);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("hung server obeys process timeout", async () => {
  const server = await startClipboardServer((_req, _res) => {});

  try {
    const result = await runClient("xclip", ["-t", "TARGETS", "-o"], {
      url: server.url,
      token: "token",
      timeout: "100",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(result.stdout.length, 0);
  } finally {
    await server.close();
  }
});

test("oversized bridge response exits nonzero without stdout", async () => {
  const server = await startClipboardServer((_req, res) => {
    res.setHeader("Content-Type", "image/png");
    res.end(Buffer.alloc(32, 1));
  });

  try {
    const result = await runClient("wl-paste", ["--type=image/png"], {
      url: server.url,
      token: "token",
      maxBytes: "16",
    });

    assert.notStrictEqual(result.code, 0);
    assert.strictEqual(result.stdout.length, 0);
  } finally {
    await server.close();
  }
});
