#!/usr/bin/env node
import React from 'react';
import { render } from 'ink';
import { App } from './app.js';

interface Options {
  apiUrl: string;
  queue?: string;
  refreshSeconds: number;
}

function parseArgs(argv: string[]): Options {
  const options: Options = {
    apiUrl: 'http://localhost:3000',
    refreshSeconds: 5
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--api') options.apiUrl = requireValue(argv, ++index, '--api');
    else if (arg === '--queue') options.queue = requireValue(argv, ++index, '--queue');
    else if (arg === '--refresh') options.refreshSeconds = Number(requireValue(argv, ++index, '--refresh'));
    else if (arg === '--help' || arg === '-h') {
      console.log('Usage: stupidclaw-tui [--api URL] [--queue SLUG] [--refresh SECONDS]');
      process.exit(0);
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!Number.isFinite(options.refreshSeconds) || options.refreshSeconds <= 0) {
    throw new Error('--refresh must be a positive number of seconds');
  }

  return options;
}

function requireValue(argv: string[], index: number, option: string): string {
  const value = argv[index];
  if (!value || value.startsWith('--')) throw new Error(`${option} requires a value`);
  return value;
}

try {
  const options = parseArgs(process.argv.slice(2));
  render(<App apiUrl={options.apiUrl} queue={options.queue} refreshSeconds={options.refreshSeconds} />);
} catch (err) {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
}

export { parseArgs };
