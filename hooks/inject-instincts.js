#!/usr/bin/env node
/**
 * SessionStart hook — inject learned instincts into a new session's context.
 *
 * Standalone extraction of the instinct-injection logic from ECC's
 * monolithic session-start.js. Depends only on the Node standard library.
 *
 * Behaviour:
 *   1. Resolve the homunculus data dir (CLV2_HOMUNCULUS_DIR / XDG_DATA_HOME /
 *      ~/.local/share/ecc-homunculus).
 *   2. Detect the current project (git origin remote hash -> projects/<hash>/),
 *      falling back to global scope when not in a git repo.
 *   3. Read instinct files from project + global instincts/{personal,inherited}.
 *   4. Dedupe by id (project scope wins), filter to confidence >= threshold,
 *      take the top N by confidence.
 *   5. Emit an "Active instincts:" block via the SessionStart hook output
 *      format (hookSpecificOutput.additionalContext on stdout).
 *
 * On any error, or when there are no qualifying instincts, it exits 0 and
 * emits an empty additionalContext — it never blocks a session.
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const INSTINCT_CONFIDENCE_THRESHOLD = 0.7;
const MAX_INJECTED_INSTINCTS = 6;

// Diagnostic logging goes to stderr so it never corrupts the stdout payload.
function log(message) {
  process.stderr.write(`${message}\n`);
}

// --- Homunculus directory resolution -------------------------------------
// Precedence: CLV2_HOMUNCULUS_DIR (absolute) -> XDG_DATA_HOME/ecc-homunculus
// (absolute) -> ~/.local/share/ecc-homunculus
function getHomunculusDir() {
  const override = process.env.CLV2_HOMUNCULUS_DIR;
  if (override) {
    if (path.isAbsolute(override)) {
      return override;
    }
    log(`[inject-instincts] CLV2_HOMUNCULUS_DIR=${override} is not absolute; ignoring`);
  }

  const xdgDataHome = process.env.XDG_DATA_HOME;
  if (xdgDataHome) {
    if (path.isAbsolute(xdgDataHome)) {
      return path.join(xdgDataHome, 'ecc-homunculus');
    }
    log(`[inject-instincts] XDG_DATA_HOME=${xdgDataHome} is not absolute; ignoring`);
  }

  return path.join(os.homedir(), '.local', 'share', 'ecc-homunculus');
}

function getProjectsDir() {
  return path.join(getHomunculusDir(), 'projects');
}

function getProjectRegistryPath() {
  return path.join(getHomunculusDir(), 'projects.json');
}

function readProjectRegistry() {
  try {
    return JSON.parse(fs.readFileSync(getProjectRegistryPath(), 'utf8'));
  } catch {
    return {};
  }
}

// --- Project-context detection -------------------------------------------
function runGit(args, cwd) {
  try {
    const result = spawnSync('git', args, {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    if (result.status !== 0) return '';
    return (result.stdout || '').trim();
  } catch {
    return '';
  }
}

function stripRemoteCredentials(remoteUrl) {
  if (!remoteUrl) return '';
  return String(remoteUrl).replace(/:\/\/[^@]+@/, '://');
}

function normalizeRemoteUrl(remoteUrl) {
  if (!remoteUrl) return '';
  const raw = String(remoteUrl);
  const isNetwork = !raw.startsWith('file://') && (raw.includes('://') || /^[^@/:]+@[^:/]+:/.test(raw));
  let normalized = stripRemoteCredentials(raw)
    .replace(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, '')
    .replace(/^[^@/:]+@([^:/]+):/, '$1/')
    .replace(/\.git\/?$/, '')
    .replace(/\/+$/, '');

  if (isNetwork) {
    normalized = normalized.toLowerCase();
  }

  return normalized;
}

function resolveProjectRoot(cwd) {
  const envRoot = process.env.CLAUDE_PROJECT_DIR;
  if (envRoot && fs.existsSync(envRoot)) {
    return path.resolve(envRoot);
  }

  const gitRoot = runGit(['rev-parse', '--show-toplevel'], cwd);
  if (gitRoot) return path.resolve(gitRoot);

  return '';
}

function computeProjectId(projectRoot) {
  const remoteUrl = stripRemoteCredentials(runGit(['remote', 'get-url', 'origin'], projectRoot));
  const hashInput = normalizeRemoteUrl(remoteUrl) || remoteUrl || projectRoot;
  return crypto.createHash('sha256').update(hashInput).digest('hex').slice(0, 12);
}

function resolveProjectContext(cwd) {
  const projectRoot = resolveProjectRoot(cwd);
  if (!projectRoot) {
    return { projectId: 'global', projectRoot: '', projectDir: getHomunculusDir(), isGlobal: true };
  }

  const registry = readProjectRegistry();
  const registryEntry = Object.values(registry).find(
    (entry) => entry && path.resolve(entry.root || '') === projectRoot,
  );
  const projectId = (registryEntry && registryEntry.id) || computeProjectId(projectRoot);
  const projectDir = path.join(getProjectsDir(), projectId);

  return { projectId, projectRoot, projectDir, isGlobal: false };
}

// --- Instinct parsing -----------------------------------------------------
function parseInstinctFile(content) {
  const instincts = [];
  let current = null;
  let inFrontmatter = false;
  let contentLines = [];

  for (const line of String(content).split('\n')) {
    if (line.trim() === '---') {
      if (inFrontmatter) {
        inFrontmatter = false;
      } else {
        if (current && current.id) {
          current.content = contentLines.join('\n').trim();
          instincts.push(current);
        }
        current = {};
        contentLines = [];
        inFrontmatter = true;
      }
      continue;
    }

    if (inFrontmatter) {
      const separatorIndex = line.indexOf(':');
      if (separatorIndex === -1) continue;
      const key = line.slice(0, separatorIndex).trim();
      let value = line.slice(separatorIndex + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (key === 'confidence') {
        const parsed = Number.parseFloat(value);
        current[key] = Number.isFinite(parsed) ? parsed : 0.5;
      } else {
        current[key] = value;
      }
    } else if (current) {
      contentLines.push(line);
    }
  }

  if (current && current.id) {
    current.content = contentLines.join('\n').trim();
    instincts.push(current);
  }

  return instincts;
}

function readInstinctsFromDir(directory, scope) {
  if (!directory || !fs.existsSync(directory)) return [];

  let entries;
  try {
    entries = fs.readdirSync(directory, { withFileTypes: true })
      .filter((entry) => entry.isFile() && /\.(ya?ml|md)$/i.test(entry.name))
      .sort((left, right) => left.name.localeCompare(right.name));
  } catch {
    return [];
  }

  const instincts = [];
  for (const entry of entries) {
    const filePath = path.join(directory, entry.name);
    try {
      const parsed = parseInstinctFile(fs.readFileSync(filePath, 'utf8'));
      for (const instinct of parsed) {
        instincts.push({
          ...instinct,
          _scopeLabel: scope,
          _sourceFile: filePath,
        });
      }
    } catch (error) {
      log(`[inject-instincts] Warning: failed to parse instinct file ${filePath}: ${error.message}`);
    }
  }

  return instincts;
}

function extractInstinctAction(content) {
  const actionMatch = String(content || '').match(/## Action\s*\n+([\s\S]+?)(?:\n## |\n---|$)/);
  const actionBlock = (actionMatch ? actionMatch[1] : String(content || '')).trim();
  const firstLine = actionBlock
    .split('\n')
    .map((line) => line.trim())
    .find(Boolean);

  return firstLine || '';
}

function summarizeActiveInstincts(observerContext) {
  const homunculusDir = getHomunculusDir();
  const globalDirs = [
    { dir: path.join(homunculusDir, 'instincts', 'personal'), scope: 'global' },
    { dir: path.join(homunculusDir, 'instincts', 'inherited'), scope: 'global' },
  ];
  const projectDirs = observerContext.isGlobal ? [] : [
    { dir: path.join(observerContext.projectDir, 'instincts', 'personal'), scope: 'project' },
    { dir: path.join(observerContext.projectDir, 'instincts', 'inherited'), scope: 'project' },
  ];

  const scopedInstincts = [
    ...projectDirs.flatMap(({ dir, scope }) => readInstinctsFromDir(dir, scope)),
    ...globalDirs.flatMap(({ dir, scope }) => readInstinctsFromDir(dir, scope)),
  ];

  const deduped = new Map();
  for (const instinct of scopedInstincts) {
    if (!instinct.id || instinct.confidence < INSTINCT_CONFIDENCE_THRESHOLD) continue;
    const existing = deduped.get(instinct.id);
    if (!existing || (existing._scopeLabel !== 'project' && instinct._scopeLabel === 'project')) {
      deduped.set(instinct.id, instinct);
    }
  }

  const ranked = Array.from(deduped.values())
    .map((instinct) => ({
      ...instinct,
      action: extractInstinctAction(instinct.content),
    }))
    .filter((instinct) => instinct.action)
    .sort((left, right) => {
      if (right.confidence !== left.confidence) return right.confidence - left.confidence;
      if (left._scopeLabel !== right._scopeLabel) return left._scopeLabel === 'project' ? -1 : 1;
      return String(left.id).localeCompare(String(right.id));
    })
    .slice(0, MAX_INJECTED_INSTINCTS);

  if (ranked.length === 0) {
    return '';
  }

  log(`[inject-instincts] Injecting ${ranked.length} instinct(s) into session context`);

  const lines = ranked.map((instinct) => {
    const scope = instinct._scopeLabel === 'project' ? 'project' : 'global';
    const confidence = `${Math.round(instinct.confidence * 100)}%`;
    return `- [${scope} ${confidence}] ${instinct.action}`;
  });

  return `Active instincts:\n${lines.join('\n')}`;
}

// --- SessionStart hook output emission -----------------------------------
function emitSessionStartPayload(additionalContext) {
  const payload = JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: String(additionalContext || ''),
    },
  });
  process.stdout.write(payload);
}

function main() {
  let additionalContext = '';
  try {
    const observerContext = resolveProjectContext(process.cwd());
    additionalContext = summarizeActiveInstincts(observerContext);
  } catch (error) {
    log(`[inject-instincts] Error: ${error.message}`);
    additionalContext = '';
  }
  emitSessionStartPayload(additionalContext);
}

main();
