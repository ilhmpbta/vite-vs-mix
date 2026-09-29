// scripts/gen-stress.mjs
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const COUNT = parseInt(process.argv[2] || '500', 10);
const ROOT = process.cwd();
const DIR = path.join(ROOT, 'resources/js/components/stress');
const UTIL_DIR = path.join(ROOT, 'resources/js/lib');

if (Number.isNaN(COUNT) || COUNT < 1) {
    console.error('Usage: node scripts/gen-stress.mjs <count>');
    process.exit(1);
}

// Shared util so every component depends on the same module (builds a dep graph)
const utilSource = `// AUTO-GENERATED. Safe to delete.
export function formatLabel(id: number, count: number): string {
    return \`item-\${id.toString().padStart(4, '0')}:n=\${count}\`;
}

export function computeWeight(id: number): number {
    return (id * 2654435761) % 2147483647;
}
`;

function componentSource(i) {
    const name = `Stress${i.toString().padStart(4, '0')}`;
    const weight = (i * 2654435761) % 2147483647;
    return `// AUTO-GENERATED. Safe to delete.
import { useEffect, useMemo, useState } from 'react';
import { formatLabel, computeWeight } from '@/lib/stress-utils';

interface ${name}Props {
    seed?: number;
    onPing?: (id: number) => void;
}

export default function ${name}({ seed = ${i}, onPing }: ${name}Props) {
    const [count, setCount] = useState(0);
    const weight = useMemo(() => computeWeight(${i}), []);
    const label = useMemo(() => formatLabel(${i}, count), [count]);

    useEffect(() => {
        if (count > 0 && onPing) onPing(${i});
    }, [count, onPing]);

    return (
        <div className="p-2 m-1 rounded border border-gray-300 dark:border-gray-700 text-xs">
            <span className="font-mono text-gray-500">${name}</span>
            <span className="ml-2">{label}</span>
            <span className="ml-2 text-gray-400">w={weight}</span>
            <button
                type="button"
                className="ml-2 px-1 rounded bg-gray-100 dark:bg-gray-800"
                onClick={() => setCount((c) => c + 1)}
            >
                +{count}
            </button>
            <span className="hidden">seed={seed}</span>
        </div>
    );
}
`;
}

async function main() {
    if (existsSync(DIR)) {
        await rm(DIR, { recursive: true, force: true });
    }
    await mkdir(DIR, { recursive: true });
    await mkdir(UTIL_DIR, { recursive: true });

    await writeFile(path.join(UTIL_DIR, 'stress-utils.ts'), utilSource, 'utf8');

    const imports = [];
    const rendered = [];

    for (let i = 1; i <= COUNT; i++) {
        const name = `Stress${i.toString().padStart(4, '0')}`;
        await writeFile(path.join(DIR, `${name}.tsx`), componentSource(i), 'utf8');
        imports.push(`import ${name} from '@/components/stress/${name}';`);
        rendered.push(`                <${name} />`);
    }

    const indexSource = `// AUTO-GENERATED. Safe to delete.
${imports.join('\n')}

export const STRESS_COMPONENT_COUNT = ${COUNT};

export function StressGrid() {
    return (
        <div className="flex flex-wrap gap-1">
${rendered.join('\n')}
        </div>
    );
}

export default StressGrid;
`;

    await writeFile(path.join(DIR, 'index.tsx'), indexSource, 'utf8');

    console.log(`Generated ${COUNT} components in ${path.relative(ROOT, DIR)}`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});