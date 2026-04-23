import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ConnectionProfile,
  ConnectionProfileSaveRequest,
  ConnectionRuntimeStatus,
  ConnectionTestRequest,
  ConnectionTestResult,
  RemoteControlApi,
} from "./remoteControlApi";

const POLL_INTERVAL_MS = 5000;

export function useRemoteControl(baseUrl: string) {
  const api = useMemo(() => new RemoteControlApi(baseUrl), [baseUrl]);

  const [profile, setProfile] = useState<ConnectionProfile | null>(null);
  const [status, setStatus] = useState<ConnectionRuntimeStatus | null>(null);
  const [testResult, setTestResult] = useState<ConnectionTestResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pollRef = useRef<number | null>(null);

  const loadInitial = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [p, s] = await Promise.all([api.getConnection(), api.getStatus()]);
      setProfile(p);
      setStatus(s);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [api]);

  const refreshStatus = useCallback(async () => {
    try {
      const s = await api.getStatus();
      setStatus(s);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [api]);

  useEffect(() => {
    void loadInitial();
  }, [loadInitial]);

  useEffect(() => {
    pollRef.current = window.setInterval(() => {
      void refreshStatus();
    }, POLL_INTERVAL_MS);
    return () => {
      if (pollRef.current !== null) {
        window.clearInterval(pollRef.current);
      }
    };
  }, [refreshStatus]);

  const saveProfile = useCallback(
    async (payload: ConnectionProfileSaveRequest) => {
      setLoading(true);
      setError(null);
      try {
        await api.saveConnection(payload);
        const p = await api.getConnection();
        setProfile(p);
      } catch (e) {
        setError((e as Error).message);
        throw e;
      } finally {
        setLoading(false);
      }
    },
    [api],
  );

  const testConnection = useCallback(
    async (payload: ConnectionTestRequest) => {
      setLoading(true);
      setError(null);
      try {
        const result = await api.testConnection(payload);
        setTestResult(result);
        return result;
      } catch (e) {
        setError((e as Error).message);
        throw e;
      } finally {
        setLoading(false);
      }
    },
    [api],
  );

  const connect = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      await api.connect();
      await refreshStatus();
    } catch (e) {
      setError((e as Error).message);
      throw e;
    } finally {
      setLoading(false);
    }
  }, [api, refreshStatus]);

  const disconnect = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      await api.disconnect();
      await refreshStatus();
    } catch (e) {
      setError((e as Error).message);
      throw e;
    } finally {
      setLoading(false);
    }
  }, [api, refreshStatus]);

  return {
    profile,
    status,
    testResult,
    loading,
    error,
    saveProfile,
    testConnection,
    connect,
    disconnect,
    refreshStatus,
  };
}
