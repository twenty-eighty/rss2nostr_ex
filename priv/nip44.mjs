#!/usr/bin/env node
/**
 * NIP-44 v2 encryption/decryption helper using nostr-tools.
 *
 * Usage: INPUT_FILE=/path/to/input.json node nip44.mjs
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

import { decrypt, encrypt, getConversationKey } from 'nostr-tools/nip44';
import { readFileSync } from 'fs';

function hexToBytes(hex) {
  if (!hex || hex.length % 2 !== 0) {
    throw new Error('invalid hex');
  }

  const bytes = new Uint8Array(hex.length / 2);

  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }

  return bytes;
}

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

    const conversationKey = getConversationKey(hexToBytes(privkey), pubkey);

    if (action === 'encrypt') {
      if (!plaintext) {
        console.log(JSON.stringify({ error: 'plaintext is required for encrypt' }));
        process.exit(1);
      }
      console.log(JSON.stringify({ result: encrypt(plaintext, conversationKey) }));
    } else if (action === 'decrypt') {
      if (!ciphertext) {
        console.log(JSON.stringify({ error: 'ciphertext is required for decrypt' }));
        process.exit(1);
      }
      console.log(JSON.stringify({ result: decrypt(ciphertext, conversationKey) }));
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
