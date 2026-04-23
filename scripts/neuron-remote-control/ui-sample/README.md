# UI Sample (React + TypeScript)

This sample shows how to integrate Neuron UI with `/api/v2/remote/*` endpoints.

## Files

- `remoteControlApi.ts`: typed API client
- `useRemoteControl.ts`: React hook for load/save/test/connect/disconnect + status polling
- `RemoteControlPage.tsx`: page component skeleton

## Integration Notes

- Replace `window.location.origin` if your API base URL differs.
- Add your own form library, design system controls, and toast notifications.
- Keep `hmacSecret` write-only in UI and never render it from server response.
- Polling interval is `5s` by default in `useRemoteControl.ts`.

## Expected Backend

Use endpoints defined in:

- `scripts/neuron-remote-control/openapi/neuron-local-remote-bootstrap.openapi.yaml`
