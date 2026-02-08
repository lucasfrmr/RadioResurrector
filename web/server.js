import express from "express";
import fs from "fs";
import path from "path";

const app = express();
const PORT = process.env.PORT || 3000;
const CONFIG_PATH = "/opt/radio/config.json";
const BUFFER_DIR = process.env.BUFFER_DIR || "/opt/radio/buffer";

app.use(express.json());
app.use(express.static(path.join(process.cwd(), "web", "public")));

const readConfig = () => {
  try {
    const data = fs.readFileSync(CONFIG_PATH, "utf8");
    return JSON.parse(data);
  } catch {
    return { streams: [], currentStream: null };
  }
};

const writeConfig = (cfg) => {
  fs.writeFileSync(
    CONFIG_PATH,
    JSON.stringify(
      {
        streams: cfg.streams || [],
        currentStream: cfg.currentStream || null,
      },
      null,
      2
    )
  );
};

app.get("/api/config", (_req, res) => {
  const cfg = readConfig();
  res.json({
    streams: cfg.streams || [],
    currentStream: cfg.currentStream || cfg.streamUrl || null,
    bufferDir: BUFFER_DIR,
  });
});

app.post("/api/stream", (req, res) => {
  const { url } = req.body || {};
  if (!url || !/^https?:\/\/.+/i.test(url)) {
    return res.status(400).json({ error: "Provide a valid http(s) URL" });
  }
  const cfg = readConfig();
  const streams = new Set(cfg.streams || []);
  streams.add(url);
  cfg.streams = Array.from(streams);
  cfg.currentStream = url;
  writeConfig(cfg);
  res.json({ ok: true, currentStream: url, streams: cfg.streams });
});

app.post("/api/stream/select", (req, res) => {
  const { url } = req.body || {};
  const cfg = readConfig();
  const streams = cfg.streams || [];
  if (!url || !streams.includes(url)) {
    return res.status(400).json({ error: "Stream not found. Add it first." });
  }
  cfg.currentStream = url;
  writeConfig(cfg);
  res.json({ ok: true, currentStream: url, streams });
});

app.post("/api/flush", (_req, res) => {
  try {
    const files = fs.readdirSync(BUFFER_DIR).filter((f) => f.endsWith(".mp3") || f === "loop.m3u");
    for (const file of files) {
      fs.rmSync(path.join(BUFFER_DIR, file), { force: true });
    }
    res.json({ ok: true, removed: files.length });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`[ui] Config UI listening on ${PORT}`);
});
