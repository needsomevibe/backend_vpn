import js from '@eslint/js';
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

const nodeGlobals = {
  Buffer: 'readonly',
  console: 'readonly',
  module: 'readonly',
  process: 'readonly',
  __dirname: 'readonly',
};

const jestGlobals = {
  describe: 'readonly',
  it: 'readonly',
  expect: 'readonly',
  beforeEach: 'readonly',
  jest: 'readonly',
};

export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**'],
  },
  js.configs.recommended,
  {
    files: ['src/**/*.ts', 'test/**/*.ts', 'prisma/**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: import.meta.dirname,
        sourceType: 'module',
      },
      globals: {
        ...nodeGlobals,
        ...jestGlobals,
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
    },
    rules: {
      ...tsPlugin.configs.recommended.rules,
    },
  },
];
