import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import tseslint from 'typescript-eslint'
import vueParser from 'vue-eslint-parser'

export default [
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, extraFileExtensions: ['.vue'] }
    }
  },
  {
    files: ['src/core/**/*.ts'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [
          { group: ['vue', 'vue-router', 'pinia'], message: 'core 必须与框架无关' },
          { group: ['@/adapters/web', '@/adapters/web/*', '../adapters/web', '../adapters/web/*', '../../adapters/web', '../../adapters/web/*'], message: 'core 不得依赖浏览器实现' }
        ]
      }],
      'no-restricted-globals': ['error',
        { name: 'window', message: '使用注入的 adapter' },
        { name: 'document', message: '使用注入的 adapter' },
        { name: 'localStorage', message: '使用 StoragePort' },
        { name: 'fetch', message: '使用 HttpTransport' },
        { name: 'navigator', message: '使用注入的 adapter' }
      ]
    }
  },
  {
    files: ['src/ui/**/*.{ts,vue}'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [{ group: ['@/adapters/web', '@/adapters/web/*'], message: 'UI 只使用 runtime/store' }]
      }]
    }
  },
  { ignores: ['dist/**', 'node_modules/**', 'e2e-results/**'] }
]
