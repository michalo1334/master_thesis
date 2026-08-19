export default {
  plugins: ['./stylelint-plugin-ds-colors/index.mjs'],
  rules: {
    'ds/no-hardcoded-colors': true,
  },
  overrides: [
    {
      files: ['*.svelte'],
      customSyntax: 'postcss-html',
    },
  ],
  ignoreFiles: [
    'css/design-tokens.css',
    'svelte/ui-kit/styles/tokens.css',
  ],
};
