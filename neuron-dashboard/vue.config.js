// eslint-disable-next-line @typescript-eslint/no-var-requires
const path = require('path')

function resolve(dir) {
  return path.join(__dirname, dir)
}

module.exports = {
  publicPath: '/web',
  lintOnSave: false,
  productionSourceMap: false,
  devServer: {
    port: 3003,
    proxy: {
      '/api/v2/ekuiper': {
        target: 'http://localhost:9081',
        changeOrigin: true,
        pathRewrite: {
          '/api/v2/ekuiper': '/',
        },
      },
      '/api/v2/remote': {
        target: process.env.VUE_APP_REMOTE_HOST || 'http://127.0.0.1:18080',
        changeOrigin: true,
        ws: false,
      },
      '/api': {
        // Keep dev server stable when VUE_APP_HOST is not provided.
        target: process.env.VUE_APP_HOST || 'http://localhost:7003',
        changeOrigin: true,
        ws: false,
      },
    },
  },
  configureWebpack: {
    resolve: {
      extensions: ['.js', '.vue', '.json'],
      alias: {
        '@': resolve('src'),
      },
    },
  },
}
