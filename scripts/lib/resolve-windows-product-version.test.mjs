import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveWindowsProductVersion } from './resolve-windows-product-version.mjs';

test('保留稳定版的数字点分版本', () => {
  assert.equal(resolveWindowsProductVersion('1.126.04524'), '1.126.04524');
});

test('移除预发布标识和构建元数据', () => {
  assert.equal(resolveWindowsProductVersion('0.0.7-vscodemo-1'), '0.0.7');
  assert.equal(resolveWindowsProductVersion('0.0.7+build.12'), '0.0.7');
});

test('拒绝不完整或非 SemVer 版本', () => {
  assert.throws(() => resolveWindowsProductVersion('0.0'));
  assert.throws(() => resolveWindowsProductVersion('release-0.0.7'));
});
