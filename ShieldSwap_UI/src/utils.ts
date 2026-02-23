import { ethers } from "ethers";
import { FIELD_SIZE } from "./constants";

// ─── Safe bigint → 0x-padded-32-byte hex ─────────────────────────────────────
function toBytes32(value: bigint): string {
  return ethers.toBeHex(value, 32);
}

// ─── Note Generation ──────────────────────────────────────────────────────────
export function generateNote(token: "TokenA" | "TokenB", denomination: "100" | "10" | "1"): {
  nullifier: string;
  secret: string;
  commitment: string;
  noteString: string;
} {
  // Use Web Crypto API directly
  const nullifierBytes = new Uint8Array(31);
  const secretBytes   = new Uint8Array(31);
  crypto.getRandomValues(nullifierBytes);
  crypto.getRandomValues(secretBytes);

  const nullifier = ethers.hexlify(nullifierBytes);
  const secret    = ethers.hexlify(secretBytes);

  // commitment = keccak256(nullifier ++ secret) % FIELD_SIZE
  const packed     = ethers.concat([nullifierBytes, secretBytes]);
  const hashBig    = BigInt(ethers.keccak256(packed));
  const commitment = toBytes32(hashBig % FIELD_SIZE);

  // New format: shieldswap-{token}-{denomination}-{nullifier}-{secret}
  const noteString = `shieldswap-${token}-${denomination}-${nullifier}-${secret}`;

  return { nullifier, secret, commitment, noteString };
}

// ─── Note Parsing ─────────────────────────────────────────────────────────────
export function parseNote(noteString: string): {
  token: "TokenA" | "TokenB";
  denomination: "100" | "10" | "1";
  nullifier: string;
  secret: string;
  commitment: string;
  nullifierHash: string;
} {
  // Format: shieldswap-TokenA-100-0x<nullifier>-0x<secret>
  const trimmed = noteString.trim();
  
  if (!trimmed.startsWith("shieldswap-")) {
    throw new Error("Invalid note format. Expected: shieldswap-TokenA-100-0x...-0x...");
  }

  const parts = trimmed.split("-");
  
  // Should have at least 5 parts: ["shieldswap", "TokenA", "100", "0x...", "0x..."]
  // But nullifier/secret may contain dashes in their hex, so we need to be careful
  if (parts.length < 5) {
    throw new Error("Invalid note: missing required parts");
  }

  const token = parts[1] as "TokenA" | "TokenB";
  const denomination = parts[2] as "100" | "10" | "1";

  if (token !== "TokenA" && token !== "TokenB") {
    throw new Error(`Invalid token: ${token}. Expected TokenA or TokenB`);
  }

  if (denomination !== "100" && denomination !== "10" && denomination !== "1") {
    throw new Error(`Invalid denomination: ${denomination}. Expected 100, 10, or 1`);
  }

  // Everything after the third part is nullifier-secret
  // Rejoin in case the hex values contained dashes
  const rest = parts.slice(3).join("-"); // "0xNULLIFIER-0xSECRET"
  
  const dashIdx = rest.indexOf("-", 2); // find '-' after '0x'
  if (dashIdx === -1) {
    throw new Error("Invalid note: missing separator between nullifier and secret");
  }

  const nullifier = rest.slice(0, dashIdx);
  const secret    = rest.slice(dashIdx + 1);

  if (!nullifier.startsWith("0x") || !secret.startsWith("0x")) {
    throw new Error("Invalid note: nullifier/secret must start with 0x");
  }

  const nullifierBytes = ethers.getBytes(nullifier);
  const secretBytes    = ethers.getBytes(secret);

  // commitment = keccak256(nullifier ++ secret) % FIELD_SIZE
  const packed     = ethers.concat([nullifierBytes, secretBytes]);
  const hashBig    = BigInt(ethers.keccak256(packed));
  const commitment = toBytes32(hashBig % FIELD_SIZE);

  // nullifierHash = keccak256(nullifier) % FIELD_SIZE
  const nullifierHashBig = BigInt(ethers.keccak256(nullifierBytes));
  const nullifierHash    = toBytes32(nullifierHashBig % FIELD_SIZE);

  return { token, denomination, nullifier, secret, commitment, nullifierHash };
}

// ─── Zero Proof ───────────────────────────────────────────────────────────────
export function makeZeroProof(): string {
  return ethers.hexlify(new Uint8Array(256));
}

// ─── Format helpers ───────────────────────────────────────────────────────────
export function formatUnits(value: bigint, decimals = 18, precision = 4): string {
  const formatted = ethers.formatUnits(value, decimals);
  const num = parseFloat(formatted);
  return num.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: precision,
  });
}

export function truncateAddress(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function now(): string {
  return new Date().toLocaleTimeString("en-US", { hour12: false });
}