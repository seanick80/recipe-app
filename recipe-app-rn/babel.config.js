module.exports = function (api) {
  api.cache(true);
  return {
    presets: [
      ['babel-preset-expo', { jsxImportSource: 'nativewind' }],
      'nativewind/babel',
    ],
    // reanimated v4 ships its babel plugin under react-native-worklets.
    plugins: ['react-native-worklets/plugin'],
  };
};
