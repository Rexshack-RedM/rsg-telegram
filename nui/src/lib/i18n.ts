import type { UiLabels } from './types';

export function translate(labels: UiLabels, key: string, replacements: Record<string, string | number> = {}): string {
  let value = labels[key] ?? key;

  for (const [name, replacement] of Object.entries(replacements)) {
    value = value.replace(new RegExp(`\\{${name}\\}`, 'g'), String(replacement));
  }

  return value;
}
