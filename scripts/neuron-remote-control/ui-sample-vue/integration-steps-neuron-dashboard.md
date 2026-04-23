# Integration Steps for neuron-dashboard Source

Use these steps when working in the separate `neuron-dashboard` source repository.

## 1) Add page and API files

Copy files:

- `ui-sample-vue/RemoteControl.vue` -> `src/views/configuration/remote-control/index.vue`
- `ui-sample-vue/remoteControlApi.js` -> `src/api/remoteControl.js`

## 2) Add route entry

Add route in your router config (example):

```js
{
  path: '/configuration/remote-control',
  name: 'remote-control',
  component: () => import('@/views/configuration/remote-control/index.vue'),
  meta: { title: 'Remote Control' }
}
```

## 3) Add left menu item

Add a menu entry under Configuration:

- label: `Remote Control`
- route: `/configuration/remote-control`

## 4) Access control

Restrict page to admin role only (same permission model used by existing configuration pages).

## 5) Backend base URL

`window.location.origin` is used by default in sample.
If dashboard proxies API via another origin/path, update API client accordingly.

## 6) Smoke test checklist

1. Open page and verify profile/status loaded.
2. Save valid config (`wss://...`).
3. Test connection and verify result panel updates.
4. Connect and verify status becomes `connected`.
5. Disconnect and verify status becomes `disconnected`.
6. Check invalid payload shows toast error.

## 7) Security requirements before production

- Never return or prefill `hmacSecret` from backend.
- Mask secret in input and logs.
- Remove any insecure TLS overrides from production build.
