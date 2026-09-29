// scripts/clean-stress.mjs
import { rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const targets = [
    'resources/js/components/stress',
    'resources/js/pages/stress.tsx',
    'resources/js/lib/stress-utils.ts',
];

for (const t of targets) {
    const p = path.join(ROOT, t);
    if (existsSync(p)) {
        await rm(p, { recursive: true, force: true });
        console.log(`removed ${t}`);
    }
}