#!/usr/bin/env node

import fs from 'node:fs';

const [productPath, identityLockPath] = process.argv.slice(2);

if (!productPath || !identityLockPath) {
  console.error('usage: node scripts/lib/validate-windows-product-identity.mjs <product.override.json> <windows-identity.lock.json>');
  process.exit(2);
}

const product = JSON.parse(fs.readFileSync(productPath, 'utf8'));
const identityLock = JSON.parse(fs.readFileSync(identityLockPath, 'utf8'));
const guidPattern = /^[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}$/i;
const innoAppIdPattern = /^\{\{([0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12})\}$/i;

const vscodiumIdentities = new Set([
  // stable Inno AppIds / context-menu CLSIDs / MSI UpgradeCode
  '763CBF88-25C6-4B10-952F-326AE657F16B',
  '88DA3577-054F-4CA1-8122-7D820494CFFB',
  '67DEE444-3D04-4258-B92A-BC1F0FF2CAE4',
  '0FD05EB4-651E-4E78-A062-515204B47A3A',
  '2E1F05D1-C245-4562-81EE-28188DB6FD17',
  '57FD70A5-1B8D-4875-9F40-C5553F094828',
  'D910D5E6-B277-4F4A-BDC5-759A34EEE25D',
  '4852FC55-4A84-4EA1-9C86-D53BE3DF83C0',
  '965370CD-253C-4720-82FC-2E6B02A53808',
  // insider Inno AppIds / context-menu CLSIDs / MSI UpgradeCode
  'EF35BB36-FA7E-4BB9-B7DA-D1E09F2DA9C9',
  'B2E0DDB2-120E-4D34-9F7E-8C688FF839A2',
  '44721278-64C6-4513-BC45-D48E07830599',
  'ED2E5618-3E7E-4888-BF3C-A6CCC84F586F',
  '20F79D0D-A9AC-4220-9A81-CE675FFB6B41',
  '2E362F92-14EA-455A-9ABD-3E656BBBFE71',
  '90AAD229-85FD-43A3-B82D-8598A88829CF',
  '7544C31C-BDBF-4DDF-B15E-F73A46D6723D',
  '1C9B7195-5A9A-43B3-B4BD-583E20498467'
]);

const appIdKeys = [
  'win32AppId',
  'win32x64AppId',
  'win32arm64AppId',
  'win32UserAppId',
  'win32x64UserAppId',
  'win32arm64UserAppId'
];

function collectGuidIdentities(configuration, sourceLabel) {
  const identities = [];
  for (const key of appIdKeys) {
    const value = configuration[key];
    const match = typeof value === 'string' ? innoAppIdPattern.exec(value) : null;
    if (!match) {
      throw new Error(`${sourceLabel}: ${key} 缺失或不是 Inno AppId 格式 {{GUID}`);
    }
    identities.push({ key, rawValue: value, value: match[1].toUpperCase() });
  }

  for (const arch of ['x64', 'arm64']) {
    const key = `win32ContextMenu.${arch}.clsid`;
    const value = configuration.win32ContextMenu?.[arch]?.clsid;
    if (typeof value !== 'string' || !guidPattern.test(value)) {
      throw new Error(`${sourceLabel}: ${key} 缺失或不是 GUID`);
    }
    identities.push({ key, rawValue: value, value: value.toUpperCase() });
  }

  if (typeof configuration.win32MsiUpgradeCode !== 'string' || !guidPattern.test(configuration.win32MsiUpgradeCode)) {
    throw new Error(`${sourceLabel}: win32MsiUpgradeCode 缺失或不是 GUID`);
  }
  identities.push({
    key: 'win32MsiUpgradeCode',
    rawValue: configuration.win32MsiUpgradeCode,
    value: configuration.win32MsiUpgradeCode.toUpperCase()
  });

  const seen = new Map();
  for (const identity of identities) {
    const previousKey = seen.get(identity.value);
    if (previousKey) {
      throw new Error(`${sourceLabel}: ${identity.key} 与 ${previousKey} 使用了重复 GUID ${identity.value}`);
    }
    seen.set(identity.value, identity.key);

    if (vscodiumIdentities.has(identity.value)) {
      throw new Error(`${sourceLabel}: ${identity.key} 仍使用 VSCodium 身份 ${identity.value}`);
    }
  }

  return identities;
}

function validateAppUserModelId(configuration, sourceLabel) {
  if (typeof configuration.win32AppUserModelId !== 'string' || configuration.win32AppUserModelId.length === 0) {
    throw new Error(`${sourceLabel}: win32AppUserModelId 缺失`);
  }
  if (/^VSCodium\./i.test(configuration.win32AppUserModelId)) {
    throw new Error(`${sourceLabel}: win32AppUserModelId 仍使用 VSCodium 身份 ${configuration.win32AppUserModelId}`);
  }
}

const lockedIdentities = collectGuidIdentities(identityLock, 'Windows 身份锁');
const productIdentities = collectGuidIdentities(product, '产品配置');
validateAppUserModelId(identityLock, 'Windows 身份锁');
validateAppUserModelId(product, '产品配置');

for (let index = 0; index < lockedIdentities.length; index++) {
  const lockedIdentity = lockedIdentities[index];
  const productIdentity = productIdentities[index];
  if (productIdentity.key !== lockedIdentity.key || productIdentity.rawValue !== lockedIdentity.rawValue) {
    throw new Error(
      `${productIdentity.key} 与 Windows 身份锁不一致：产品配置 ${productIdentity.rawValue}，锁定值 ${lockedIdentity.rawValue}`
    );
  }
}

if (product.win32AppUserModelId !== identityLock.win32AppUserModelId) {
  throw new Error(
    `win32AppUserModelId 与 Windows 身份锁不一致：产品配置 ${product.win32AppUserModelId}，锁定值 ${identityLock.win32AppUserModelId}`
  );
}

console.log(`==> Windows 产品身份锁校验通过（${productIdentities.length} 个 GUID + AppUserModelId）`);
