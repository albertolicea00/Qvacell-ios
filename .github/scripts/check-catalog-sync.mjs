#!/usr/bin/env node
// Compares the STRUCTURE of this repo's codes.json against the counterpart
// platform's codes.json (fetched from its raw GitHub URL). "Structure" means:
// which categories/groups exist and in what order, and per-code: id, code
// (dial string), type, requiresInput, inputPlaceholder, noConfirmCode,
// smsBody, options, isSubscription, variants. Cosmetic/presentation fields
// (icon, price, compact, showsNumber, title, details) are intentionally
// ignored — those are allowed to differ per-platform (e.g. SF Symbol vs.
// Material icon names) without triggering a drift report.
//
// Exit codes: 0 = in sync, 1 = drift found (writes REPORT_FILE), 2 = counterpart
// catalog unreachable (not a failure — nothing to compare against).

import { readFileSync, writeFileSync } from "node:fs";

const LOCAL_PATH = process.env.LOCAL_CATALOG_PATH;
const REMOTE_URL = process.env.REMOTE_CATALOG_URL;
const REPORT_FILE = process.env.REPORT_FILE ?? "catalog-sync-report.md";
const REMOTE_LABEL = process.env.REMOTE_LABEL ?? "counterpart";

if (!LOCAL_PATH || !REMOTE_URL) {
  console.error("LOCAL_CATALOG_PATH and REMOTE_CATALOG_URL must be set.");
  process.exit(2);
}

function structuralCode(code) {
  return {
    id: code.id,
    code: code.code,
    type: code.type,
    requiresInput: code.requiresInput ?? false,
    inputPlaceholder: code.inputPlaceholder ?? null,
    noConfirmCode: code.noConfirmCode ?? null,
    smsBody: code.smsBody ?? null,
    options: code.options ?? null,
    isSubscription: code.isSubscription ?? false,
    variants: (code.variants ?? []).map((v) => ({ label: v.label, smsBody: v.smsBody })),
  };
}

// Flattens a catalog into an ordered list of {categoryId, groupName, ...structuralCode}
// so both "which codes exist" and "where they live" are captured.
function flatten(catalog) {
  const rows = [];
  const categoryOrder = [];
  for (const category of catalog.categories ?? []) {
    categoryOrder.push(category.id);
    for (const group of category.groups ?? []) {
      const groupName = group.name ?? null;
      for (const code of group.codes ?? []) {
        rows.push({ categoryId: category.id, groupName, ...structuralCode(code) });
      }
    }
  }
  return { categoryOrder, rows };
}

function diffCatalogs(local, remote) {
  const lines = [];

  if (JSON.stringify(local.categoryOrder) !== JSON.stringify(remote.categoryOrder)) {
    lines.push(
      `- **Category order/set differs.**\n  - this repo: \`${local.categoryOrder.join(", ")}\`\n  - ${REMOTE_LABEL}: \`${remote.categoryOrder.join(", ")}\``
    );
  }

  const localById = new Map(local.rows.map((r) => [r.id, r]));
  const remoteById = new Map(remote.rows.map((r) => [r.id, r]));

  for (const id of localById.keys()) {
    if (!remoteById.has(id)) {
      lines.push(`- Code \`${id}\` exists here but is missing from ${REMOTE_LABEL}.`);
    }
  }
  for (const id of remoteById.keys()) {
    if (!localById.has(id)) {
      lines.push(`- Code \`${id}\` exists in ${REMOTE_LABEL} but is missing here.`);
    }
  }

  for (const [id, localRow] of localById) {
    const remoteRow = remoteById.get(id);
    if (!remoteRow) continue;
    const { id: _l, ...localRest } = localRow;
    const { id: _r, ...remoteRest } = remoteRow;
    if (JSON.stringify(localRest) !== JSON.stringify(remoteRest)) {
      lines.push(
        `- Code \`${id}\` differs in structure:\n  - this repo: \`${JSON.stringify(localRest)}\`\n  - ${REMOTE_LABEL}: \`${JSON.stringify(remoteRest)}\``
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
  console.error(`Could not fetch/parse ${REMOTE_LABEL} catalog (${REMOTE_URL}): ${err.message}`);
  process.exit(2);
}

const localJson = JSON.parse(readFileSync(LOCAL_PATH, "utf8"));

const local = flatten(localJson);
const remote = flatten(remoteJson);
const diffLines = diffCatalogs(local, remote);

if (diffLines.length === 0) {
  console.log(`USSD catalog structure is in sync with ${REMOTE_LABEL}.`);
  process.exit(0);
}

const report = [
  `The USSD catalog structure here no longer matches ${REMOTE_LABEL}'s \`codes.json\`.`,
  "",
  "Only structural fields were compared (id, code, type, requiresInput, inputPlaceholder,",
  "noConfirmCode, smsBody, options, isSubscription, variants, and category/group placement).",
  "Cosmetic fields (icon, price, compact, showsNumber, title, details) are ignored on purpose.",
  "",
  "## Differences",
  "",
  ...diffLines,
].join("\n");

writeFileSync(REPORT_FILE, report + "\n");
console.error(report);
process.exit(1);
