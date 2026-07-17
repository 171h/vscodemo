#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const STATE_FILE = path.join(ROOT, 'build', '.dev-prepare-state.json');
const VSCODE_DIR = path.join(ROOT, 'vscode');
const IGNORED_NAMES = new Set([
  '.git',
  '.pnpm-store',
  '.turbo',
  '.venv',
  'node_modules',
]);

function hashPath(relativePath) {
  const hash = crypto.createHash('sha256');
  const absolutePath = path.join(ROOT, relativePath);

  function visit(currentPath, logicalPath) {
    if (!fs.existsSync(currentPath)) {
      hash.update(`missing\0${logicalPath}\0`);
      return;
    }

    const stat = fs.lstatSync(currentPath);
    if (stat.isDirectory()) {
      hash.update(`dir\0${logicalPath}\0`);
      for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })
        .filter(entry => !IGNORED_NAMES.has(entry.name))
        .sort((a, b) => a.name.localeCompare(b.name))) {
        visit(path.join(currentPath, entry.name), `${logicalPath}/${entry.name}`);
      }
      return;
    }

    if (stat.isSymbolicLink()) {
      hash.update(`link\0${logicalPath}\0${fs.readlinkSync(currentPath)}\0`);
      return;
    }

    hash.update(`file\0${logicalPath}\0${stat.mode}\0`);
    hash.update(fs.readFileSync(currentPath));
    hash.update('\0');
  }

  visit(absolutePath, relativePath.replaceAll('\\', '/'));
  return hash.digest('hex');
}

function git(args, encoding = 'utf8') {
  const result = spawnSync('git', ['-C', VSCODE_DIR, ...args], {
    encoding,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    const detail = result.error?.message || String(result.stderr || '').trim();
    throw new Error(`git ${args.join(' ')} 执行失败: ${detail}`);
  }
  return result.stdout;
}

function vscodeSignature() {
  const hash = crypto.createHash('sha256');
  hash.update(git(['rev-parse', 'HEAD']));
  const status = git(['status', '--porcelain=v1', '-z', '--untracked-files=all']);
  hash.update(status);

  // 哈希所有仍存在的变更文件内容；删除项只需由 status 中的路径与状态表示。
  // 相比生成完整 binary diff，这在裁剪大量上游文件的工作副本上快得多。
  const changedPaths = status.split('\0').filter(Boolean).map((entry) =>
    /^[ MADRCU?!]{2} /.test(entry) ? entry.slice(3) : entry
  );
  for (const relativePath of changedPaths) {
    const absolutePath = path.join(VSCODE_DIR, relativePath);
    hash.update(`changed\0${relativePath}\0`);
    if (fs.existsSync(absolutePath) && fs.lstatSync(absolutePath).isFile()) {
      hash.update(fs.readFileSync(absolutePath));
    }
    hash.update('\0');
  }
  return hash.digest('hex');
}

function sourceState() {
  return {
    patches: hashPath('patches'),
    product: hashPath('product')
  };
}

function capture() {
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  fs.writeFileSync(STATE_FILE, `${JSON.stringify({
    version: 1,
    vscodeHead: git(['rev-parse', 'HEAD']).trim(),
    vscodeSignature: vscodeSignature(),
    sources: sourceState()
  }, null, 2)}\n`);
  console.log('开发态快照已更新');
}

function inspect() {
  if (!fs.existsSync(STATE_FILE)) {
    console.log(JSON.stringify({ exists: false }));
    return;
  }

  const saved = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  const currentSources = sourceState();
  const changed = Object.keys(currentSources)
    .filter(key => currentSources[key] !== saved.sources?.[key]);
  console.log(JSON.stringify({
    exists: true,
    headMatches: saved.vscodeHead === git(['rev-parse', 'HEAD']).trim(),
    worktreeMatches: saved.vscodeSignature === vscodeSignature(),
    changed
  }));
}

const command = process.argv[2];
try {
  if (command === 'capture') {
    capture();
  } else if (command === 'inspect') {
    inspect();
  } else {
    console.error('用法: node scripts/lib/dev-state.mjs <capture|inspect>');
    process.exit(1);
  }
} catch (error) {
  console.error(`错误: ${error.message}`);
  process.exit(1);
}
