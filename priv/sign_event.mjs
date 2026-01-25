#!/usr/bin/env node
/**
 * Signs a Nostr event using nostr-tools.
 *
 * Usage: INPUT_FILE=/path/to/input.json node sign_event.mjs
 *    or: echo '{"event": {...}, "privkey": "hex..."}' | node sign_event.mjs
 *
 * Input JSON:
 *   - event: unsigned event object (pubkey, created_at, kind, tags, content)
 *   - privkey: 32-byte private key as hex string
 *
 * Output JSON:
 *   - id: event ID
 *   - sig: BIP340 Schnorr signature
 *   - pubkey: derived public key
 */

import { finalizeEvent, getPublicKey } from 'nostr-tools/pure';
import { hexToBytes } from '@noble/hashes/utils';
import { readFileSync } from 'fs';

async function main() {
  let input = '';

  // Read from file if INPUT_FILE env var is set, otherwise from stdin
  const inputFile = process.env.INPUT_FILE;
  if (inputFile) {
    input = readFileSync(inputFile, 'utf8');
  } else {
    for await (const chunk of process.stdin) {
      input += chunk;
    }
  }

  try {
    const { event, privkey } = JSON.parse(input);

    if (!privkey) {
      console.error(JSON.stringify({ error: 'privkey is required' }));
      process.exit(1);
    }

    const privkeyBytes = hexToBytes(privkey);
    const pubkey = getPublicKey(privkeyBytes);

    // Build unsigned event
    const unsignedEvent = {
      kind: event.kind,
      created_at: event.created_at,
      tags: event.tags || [],
      content: event.content || '',
      pubkey: pubkey
    };

    // Sign and finalize the event
    const signedEvent = finalizeEvent(unsignedEvent, privkeyBytes);

    // Output result
    console.log(JSON.stringify({
      id: signedEvent.id,
      sig: signedEvent.sig,
      pubkey: signedEvent.pubkey
    }));

  } catch (err) {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();
