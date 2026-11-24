#!/usr/bin/env bun
// Fails when a row of spec/features.md lacks an id, repeats one, lacks a status for a platform, or says `no` without a reason.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const statuses = new Set(["shipped", "planned", "no"]);
const platforms = ["iOS", "Svelte", "React"];

const found: string[] = [];
const seen = new Set<string>();
let columns: string[] = [];
for (const line of readFileSync(join(import.meta.dir, "../spec/features.md"), "utf8")
  .split("\n")
  .map((row) => row.trim())) {
  if (!line.startsWith("|")) continue;
  const cells = line
    .slice(1, -1)
    .split("|")
    .map((cell) => cell.trim());
  if (cells[0] === "ID") {
    columns = cells;
    continue;
  }
  if (/^:?-+:?$/.test(cells[0]!)) continue;
  const row = Object.fromEntries(columns.map((column, index) => [column, cells[index] ?? ""]));
  const id = row.ID!;
  if (cells.length !== columns.length)
    found.push(`${id}: ${cells.length} cells for ${columns.length} columns`);
  if (!id) found.push(`"${row.Feature}": no id`);
  if (seen.has(id)) found.push(`${id}: duplicate id`);
  seen.add(id);
  if (!row.Feature) found.push(`${id}: no feature`);
  for (const platform of platforms) {
    if (!statuses.has(row[platform]!)) found.push(`${id}: ${platform} status "${row[platform]}"`);
  }
  if (platforms.some((platform) => row[platform] === "no") && !row.Notes)
    found.push(`${id}: a "no" without a reason`);
}
if (seen.size === 0) found.push("no feature rows");
if (found.length > 0) {
  console.error(`spec/features.md:\n${found.join("\n")}`);
  process.exit(1);
}
