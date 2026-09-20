#!/usr/bin/env node
// Compares this repo's wifi_navigation_rooms.json against the counterpart
// platform's copy (fetched from its raw GitHub URL). Unlike codes.json there
// are no cosmetic/presentation fields in this file (no icons) — every field
// is data (province, room name/address/positions, hotspot municipality/spots)
// — so the whole structure is compared, not a filtered subset.
//
// NOTE: this checks the two platforms against EACH OTHER, not against
// ETECSA's own site — that's what wifi-rooms-sync-check.yml already does.
//
// Exit codes: 0 = in sync, 1 = drift found (writes REPORT_FILE), 2 = counterpart
// file unreachable (not a failure — nothing to compare against).

import { readFileSync, writeFileSync } from "node:fs";

const LOCAL_PATH = process.env.LOCAL_CATALOG_PATH;
const REMOTE_URL = process.env.REMOTE_CATALOG_URL;
const REPORT_FILE = process.env.REPORT_FILE ?? "wifi-catalog-sync-report.md";
const REMOTE_LABEL = process.env.REMOTE_LABEL ?? "counterpart";

if (!LOCAL_PATH || !REMOTE_URL) {
  console.error("LOCAL_CATALOG_PATH and REMOTE_CATALOG_URL must be set.");
  process.exit(2);
}

function normalizeRoom(room) {
  return { name: room.name, address: room.address ?? null, positions: room.positions ?? null };
}

function normalizeHotspotGroup(group) {
  return { municipality: group.municipality, spots: [...(group.spots ?? [])].sort() };
}

// Flattens into a map keyed by province name so a per-province diff is possible.
function flatten(catalog) {
  const provinces = Array.isArray(catalog) ? catalog : catalog.provinces ?? [];
  const byProvince = new Map();
  for (const p of provinces) {
    byProvince.set(p.province, {
      rooms: (p.rooms ?? []).map(normalizeRoom),
      hotspots: (p.hotspots ?? []).map(normalizeHotspotGroup),
    });
  }
  return byProvince;
}

function diffCatalogs(local, remote) {
  const lines = [];
  const provinceNames = new Set([...local.keys(), ...remote.keys()]);

  for (const province of provinceNames) {
    const localData = local.get(province);
    const remoteData = remote.get(province);
    if (!remoteData) {
      lines.push(`- Province \`${province}\` exists here but is missing from ${REMOTE_LABEL}.`);
      continue;
    }
    if (!localData) {
      lines.push(`- Province \`${province}\` exists in ${REMOTE_LABEL} but is missing here.`);
      continue;
    }
    if (JSON.stringify(localData) !== JSON.stringify(remoteData)) {
      lines.push(
        `- Province \`${province}\` differs:\n  - this repo: \`${JSON.stringify(localData)}\`\n  - ${REMOTE_LABEL}: \`${JSON.stringify(remoteData)}\``
      );
    }
  }

  return lines;
}

let remoteJson;
try {
  const res = await fetch(REMOTE_URL);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  remoteJson = await res.json();
} catch (err) {
  console.error(`Could not fetch/parse ${REMOTE_LABEL} wifi rooms file (${REMOTE_URL}): ${err.message}`);
  process.exit(2);
}

const localJson = JSON.parse(readFileSync(LOCAL_PATH, "utf8"));

const local = flatten(localJson);
const remote = flatten(remoteJson);
const diffLines = diffCatalogs(local, remote);

if (diffLines.length === 0) {
  console.log(`WiFi navigation rooms directory is in sync with ${REMOTE_LABEL}.`);
  process.exit(0);
}

const report = [
  `The bundled WiFi navigation rooms directory here no longer matches ${REMOTE_LABEL}'s`,
  "\`wifi_navigation_rooms.json\`.",
  "",
  "## Differences",
  "",
  ...diffLines,
].join("\n");

writeFileSync(REPORT_FILE, report + "\n");
console.error(report);
process.exit(1);
