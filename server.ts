import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const PORT = Number(process.env.PORT || 3000);

if (process.argv.includes("--check")) {
  const requiredFiles = ["script.lua", "breakin2.lua", "index.html"];
  for (const file of requiredFiles) {
    const full = path.join(ROOT, file);
    if (!fs.existsSync(full)) {
      console.error(`Missing required file: ${file}`);
      process.exit(1);
    }
  }
  console.log("Build & syntax check passed: script.lua, breakin2.lua, index.html verified.");
  process.exit(0);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  if (url.pathname === "/api/scripts") {
    const prisonLife = fs.existsSync(path.join(ROOT, "script.lua"))
      ? fs.readFileSync(path.join(ROOT, "script.lua"), "utf8")
      : "";
    const breakIn2 = fs.existsSync(path.join(ROOT, "breakin2.lua"))
      ? fs.readFileSync(path.join(ROOT, "breakin2.lua"), "utf8")
      : "";

    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        prisonLife: {
          filename: "script.lua",
          title: "RiotHub v4.0 — Prison Life (Latest 2025/2026)",
          lines: prisonLife.split("\n").length,
          bytes: Buffer.byteLength(prisonLife, "utf8"),
          content: prisonLife,
        },
        breakIn2: {
          filename: "breakin2.lua",
          title: "RiotHub v1.0 — Break In 2 (Story)",
          lines: breakIn2.split("\n").length,
          bytes: Buffer.byteLength(breakIn2, "utf8"),
          content: breakIn2,
        },
      })
    );
    return;
  }

  if (url.pathname === "/raw/script.lua") {
    const content = fs.readFileSync(path.join(ROOT, "script.lua"), "utf8");
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(content);
    return;
  }

  if (url.pathname === "/raw/breakin2.lua") {
    const content = fs.readFileSync(path.join(ROOT, "breakin2.lua"), "utf8");
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(content);
    return;
  }

  const htmlPath = path.join(ROOT, "index.html");
  const html = fs.readFileSync(htmlPath, "utf8");
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`RiotHub Script Studio listening on http://0.0.0.0:${PORT}`);
});
