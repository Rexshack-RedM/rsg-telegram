import { mockFetchNui, isMockEnvironment } from './mock';

const RESOURCE_NAME = 'rsg-telegram';

/**
 * Posts to a registered NUI callback and resolves with its response.
 * Falls back to an in-browser mock outside the CEF runtime so the UI
 * can be developed and previewed with `npm run dev`.
 */
export async function fetchNui<TResponse = unknown, TData extends object = Record<string, unknown>>(
  callback: string,
  data: TData = {} as TData,
): Promise<TResponse> {
  if (isMockEnvironment()) {
    return mockFetchNui<TResponse>(callback, data);
  }

  const response = await fetch(`https://${RESOURCE_NAME}/${callback}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });

  return (await response.json()) as TResponse;
}
