#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

/**
 * Windows 的 Inno VersionInfoVersion 与 MSI ProductVersion 只接受数字点分版本。
 * 发布 tag 仍保留完整 SemVer；这里只取 major.minor.patch 供 Windows 元数据使用。
 */
export function resolveWindowsProductVersion(releaseVersion) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?$/.exec(releaseVersion);
  if (!match) {
    throw new Error(`无法从发布版本生成 Windows 数字产品版本: ${releaseVersion}`);
  }

  return match.slice(1, 4).join('.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(resolveWindowsProductVersion(process.argv[2] ?? ''));
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }
}
