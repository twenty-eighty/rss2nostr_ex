#!/usr/bin/env node
/**
 * NIP-04 encryption/decryption helper using nostr-tools.
 *
 * Usage: INPUT_FILE=/path/to/input.json node nip04.mjs
 *
 * Input JSON for encrypt:
 *   { "action": "encrypt", "privkey": "hex", "pubkey": "hex", "plaintext": "..." }
 *
 * Input JSON for decrypt:
 *   { "action": "decrypt", "privkey": "hex", "pubkey": "hex", "ciphertext": "..." }
 *
 * Output JSON:
 *   { "result": "..." } or { "error": "..." }
 */

import { nip04 } from 'nostr-tools';
import { hexToBytes } from '@noble/hashes/utils';
import { readFileSync } from 'fs';

async function main() {
  let input = '';

  const inputFile = process.env.INPUT_FILE;
  if (inputFile) {
    input = readFileSync(inputFile, 'utf8');
  } else {
    for await (const chunk of process.stdin) {
      input += chunk;
    }
  }

  try {
    const data = JSON.parse(input);
    const { action, privkey, pubkey, plaintext, ciphertext } = data;

    if (!privkey || !pubkey) {
      console.log(JSON.stringify({ error: 'privkey and pubkey are required' }));
      process.exit(1);
    }

    const privkeyBytes = hexToBytes(privkey);

    if (action === 'encrypt') {
      if (!plaintext) {
        console.log(JSON.stringify({ error: 'plaintext is required for encrypt' }));
        process.exit(1);
      }
      const encrypted = await nip04.encrypt(privkeyBytes, pubkey, plaintext);
      console.log(JSON.stringify({ result: encrypted }));
    } else if (action === 'decrypt') {
      if (!ciphertext) {
        console.log(JSON.stringify({ error: 'ciphertext is required for decrypt' }));
        process.exit(1);
      }
      const decrypted = await nip04.decrypt(privkeyBytes, pubkey, ciphertext);
      console.log(JSON.stringify({ result: decrypted }));
    } else {
      console.log(JSON.stringify({ error: 'action must be encrypt or decrypt' }));
      process.exit(1);
    }
  } catch (err) {
    console.log(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();
