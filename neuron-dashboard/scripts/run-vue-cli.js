#!/usr/bin/env node

/* eslint-disable @typescript-eslint/no-var-requires */
const { spawn } = require('child_process')
const path = require('path')

const argv = process.argv.slice(2)
const envArgPattern = /^[A-Z_][A-Z0-9_]*=.*/

const envOverrides = {}
const cliArgs = []

for (const token of argv) {
  if (envArgPattern.test(token)) {
    const idx = token.indexOf('=')
    const key = token.slice(0, idx)
    const value = token.slice(idx + 1)
    envOverrides[key] = value
  } else {
    cliArgs.push(token)
  }
}

const baseNodeOptions = process.env.NODE_OPTIONS || ''
const legacyFlag = '--openssl-legacy-provider'
const nodeOptions = baseNodeOptions.includes(legacyFlag) ? baseNodeOptions : `${baseNodeOptions} ${legacyFlag}`.trim()

const env = {
  ...process.env,
  ...envOverrides,
  NODE_OPTIONS: nodeOptions,
}

const vueCliBin = path.join(__dirname, '..', 'node_modules', '.bin', 'vue-cli-service')

const child = spawn(vueCliBin, cliArgs, {
  stdio: 'inherit',
  env,
  shell: false,
})

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal)
    return
  }
  process.exit(code == null ? 1 : code)
})
