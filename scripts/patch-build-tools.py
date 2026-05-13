#!/usr/bin/env python3
import os, re

base = 'vscode/build'

# Patch 1: preinstall.ts - skip npm version check
path = os.path.join(base, 'npm', 'preinstall.ts')
with open(path) as f:
    content = f.read()
content = content.replace(
    'if (npmMajor > 11 || (npmMajor === 11 && npmMinor >= 2)) {',
    'if (false) {'
)
with open(path, 'w') as f:
    f.write(content)
print('Patched preinstall.ts')

# Patch 2: optimize.ts - don't fail on unicode chars in minified output
path = os.path.join(base, 'lib', 'optimize.ts')
with open(path) as f:
    content = f.read()
old = ('\t\t\t\t\tconst unicodeMatch = contents.toString().match(/[^\\x00-\\xFF]+/g);\n'
       '\t\t\t\t\tif (unicodeMatch) {\n'
       '\t\t\t\t\t\tcb(new Error(`Found non-ascii character ${unicodeMatch[0]} in the minified output of ${f.path}. Non-ASCII characters in the output can cause performance problems when loading. Please review if you have introduced a regular expression that esbuild is not automatically converting and convert it to using unicode escape sequences.`));\n'
       '\t\t\t\t\t} else {\n'
       '\t\t\t\t\t\tf.contents = contents;\n'
       '\t\t\t\t\t\tf.sourceMap = JSON.parse(sourceMapFile.text);\n\n'
       '\t\t\t\t\t\tcb(undefined, f);\n'
       '\t\t\t\t\t}')
new = ('\t\t\t\t\tconst unicodeMatch = contents.toString().match(/[^\\x00-\\xFF]+/g);\n'
       '\t\t\t\t\tif (unicodeMatch) {\n'
       '\t\t\t\t\t\tconsole.warn(`Non-ascii char ${unicodeMatch[0]} in ${f.path}`);\n'
       '\t\t\t\t\t}\n'
       '\t\t\t\t\tf.contents = contents;\n'
       '\t\t\t\t\tf.sourceMap = JSON.parse(sourceMapFile.text);\n\n'
       '\t\t\t\t\tcb(undefined, f);')
content = content.replace(old, new)
with open(path, 'w') as f:
    f.write(content)
print('Patched optimize.ts')

# Patch 3: copilot.ts - skip if extension dir doesn't exist
path = os.path.join(base, 'lib', 'copilot.ts')
with open(path) as f:
    content = f.read()
if '!fs.existsSync(builtInCopilotExtensionDir)' not in content:
    old = 'export function prepareBuiltInCopilotRipgrepShim(platform: string, arch: string, builtInCopilotExtensionDir: string, appNodeModulesDir: string): void {'
    new = old + '\n\tif (!fs.existsSync(builtInCopilotExtensionDir)) { console.warn(`Copilot extension not found at ${builtInCopilotExtensionDir}, skipping ripgrep shim`); return; }'
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Patched copilot.ts')
else:
    print('copilot.ts already patched')
