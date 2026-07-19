#!/usr/bin/env node

import fs from 'node:fs';

const [manifestPath, productPath] = process.argv.slice(2);

if (!manifestPath || !productPath) {
	console.error('usage: node scripts/lib/patch-windows-visual-elements.mjs <VisualElementsManifest.xml> <product.json>');
	process.exit(2);
}

const product = JSON.parse(fs.readFileSync(productPath, 'utf8'));
if (typeof product.nameShort !== 'string' || product.nameShort.length === 0) {
	throw new Error(`${productPath}: nameShort is required to set the Windows tile title`);
}

const escapeXmlAttribute = value => value.replace(/[&<>"']/g, character => ({
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&apos;'
})[character]);

const manifest = fs.readFileSync(manifestPath, 'utf8');
const updatedManifest = manifest.replace(
	/ShortDisplayName="[^"]*"/,
	`ShortDisplayName="${escapeXmlAttribute(product.nameShort)}"`
);

if (updatedManifest === manifest) {
	throw new Error(`${manifestPath}: ShortDisplayName attribute not found`);
}

fs.writeFileSync(manifestPath, updatedManifest);
