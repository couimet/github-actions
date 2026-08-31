#!/usr/bin/env node
'use strict';

// Build an effective markdownlint-cli2 options file that registers the custom
// rule markdownlint-rule-force-align-table-columns (MD060A) so --fix can
// auto-align tables. cli2 only activates custom rules listed in the config it
// reads; this helper reads the consumer's config, guarantees the rule appears
// in `customRules`, and writes the result to a temporary file next to the
// source so relative `extends`, `customRules`, `globs`, `ignores`, and
// `modulePaths` still resolve. The source config is never modified.
//
// Usage: node inject-rule.cjs <source-config> <target-json>
//
// Exit codes:
//   0 + target written  injection succeeded (caller passes --config <target>)
//   0 + stdout "SKIP"   the rule is not resolvable from this action's
//                       node_modules, so the caller keeps today's behavior
//   1                   the source config could not be parsed

const fs = require('node:fs');
const path = require('node:path');

const RULE_NAME = 'markdownlint-rule-force-align-table-columns';

const [, , sourceArg, targetArg] = process.argv;
if (!sourceArg || !targetArg) {
  process.stderr.write(`usage: node ${path.basename(process.argv[1])} <source-config> <target-json>\n`);
  process.exit(2);
}

// The rule is installed as a devDependency of this action. When it is not
// resolvable (e.g. a markdownlint-version override that installs cli2 globally
// without the rule), skip injection so linting never breaks.
try {
  require.resolve(RULE_NAME);
} catch {
  process.stdout.write('SKIP\n');
  process.exit(0);
}

// Strip JSONC (comments and trailing commas) down to plain JSON.
function jsoncToJson(text) {
  let out = '';
  let inString = false;
  let escape = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = text[i + 1];
    if (inString) {
      out += ch;
      if (escape) {
        escape = false;
      } else if (ch === '\\') {
        escape = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === '/' && next === '/') {
      while (i < text.length && text[i] !== '\n') {
        i++;
      }
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) {
        i++;
      }
      i++;
      continue;
    }
    if (ch === ',') {
      // Drop a trailing comma when the next non-whitespace token closes a value.
      let j = i + 1;
      while (j < text.length && /\s/.test(text[j])) {
        j++;
      }
      if (text[j] === '}' || text[j] === ']') {
        continue;
      }
    }
    out += ch;
  }
  return out;
}

const source = path.resolve(sourceArg);
const target = path.resolve(targetArg);

let parsed;
try {
  parsed = JSON.parse(jsoncToJson(fs.readFileSync(source, 'utf8')));
} catch (error) {
  process.stderr.write(`inject-rule: cannot parse ${source}: ${error.message}\n`);
  process.exit(1);
}

// cli2 treats .markdownlint-cli2.* as options files and .markdownlint.* as
// config files. A config file has rule IDs at the top level, so wrap it in an
// options `config` object; anything else is treated as an options file.
const basename = path.basename(source);
const effective = /^\.markdownlint\./.test(basename) ? { config: parsed } : parsed;

const customRules = Array.isArray(effective.customRules) ? effective.customRules.slice() : [];
if (!customRules.includes(RULE_NAME)) {
  customRules.push(RULE_NAME);
}
effective.customRules = customRules;

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, `${JSON.stringify(effective, null, 2)}\n`);
