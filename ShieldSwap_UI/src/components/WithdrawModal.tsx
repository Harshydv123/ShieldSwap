import React, { useState } from "react";
import { ethers } from "ethers";
import { useWalletClient } from "wagmi";
import { ADDRESSES, SHIELD_POOL_ABI } from "../constants";
import { parseNote, makeZeroProof } from "../utils";

type Step = "idle" | "parsed" | "withdrawing" | "success" | "error";

interface Props {
  onClose: () => void;
}

export default function WithdrawModal({ onClose }: Props) {
  const { data: walletClient } = useWalletClient();

  const [step, setStep] = useState<Step>("idle");
  const [noteInput, setNoteInput] = useState("");
  const [recipient, setRecipient] = useState("");
  const [parsed, setParsed] = useState<{
    token: "TokenA" | "TokenB";
    denomination: "100" | "10" | "1";
    nullifier: string;
    secret: string;
    commitment: string;
    nullifierHash: string;
  } | null>(null);
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");

  const handleParse =async () => {
    try {
      const result = await parseNote(noteInput);
      setParsed(result);
      setStep("parsed");
      setError("");
    } catch (e: any) {
      setError(e.message || "Invalid note");
    }
  };

  const handleWithdraw = async () => {
    if (!walletClient || !parsed) return;
    if (!ethers.isAddress(recipient)) {
      setError("Invalid recipient address");
      return;
    }

    try {
      setStep("withdrawing");
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();

      // Get the correct pool address based on parsed note
      const poolKey = `${parsed.token}_${parsed.denomination}` as keyof typeof ADDRESSES.ShieldPools;
      const poolAddress = ADDRESSES.ShieldPools[poolKey];

      const pool = new ethers.Contract(poolAddress, SHIELD_POOL_ABI, signer);

      const root = await pool.getLastRoot();
      const proof = makeZeroProof();

      const tx = await pool.withdraw(
        proof,
        root,
        parsed.nullifierHash,
        recipient,
        ethers.ZeroAddress,
        0
      );
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("success");
      
      // Trigger balance update
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      setError(e?.message || "Withdraw failed");
      setStep("error");
    }
  };

  const getTokenDisplay = () => {
    if (!parsed) return "";
    return parsed.token === "TokenA" ? "Mock ETH" : "Mock BTC";
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close" onClick={onClose}>✕</button>

        <div className="modal-header">
          <span className="modal-icon">🔄</span>
          <h2>Withdraw</h2>
          <p className="modal-sub">Privately withdraw to any address</p>
        </div>

        {/* Idle: paste note */}
        {(step === "idle" || step === "parsed") && (
          <div className="modal-section">
            <label className="input-label">Paste your note</label>
            <textarea
              className="modal-textarea"
              placeholder="shieldswap-TokenA-100-0x...-0x..."
              value={noteInput}
              onChange={(e) => {
                setNoteInput(e.target.value);
                setStep("idle");
                setParsed(null);
              }}
              rows={3}
            />

            {error && <div className="error-inline">{error}</div>}

            {step === "idle" && (
              <button className="btn-primary" onClick={handleParse} disabled={!noteInput.trim()}>
                Parse Note →
              </button>
            )}

            {step === "parsed" && parsed && (
              <>
                <div className="parsed-info">
                  <div className="parsed-row">
                    <span className="label-small">Token:</span>
                    <span className="mono-small">
                      {parsed.token === "TokenA" ? "TokenA (Mock ETH)" : "TokenB (Mock BTC)"}
                    </span>
                  </div>
                  <div className="parsed-row">
                    <span className="label-small">Amount:</span>
                    <span className="mono-small">{parsed.denomination} {getTokenDisplay()}</span>
                  </div>
                  <div className="parsed-row">
                    <span className="label-small">Commitment:</span>
                    <span className="mono-small">{parsed.commitment.slice(0, 18)}...{parsed.commitment.slice(-6)}</span>
                  </div>
                </div>

                <label className="input-label" style={{ marginTop: "1rem" }}>Recipient Address</label>
                <input
                  className="modal-input"
                  placeholder="0x... (address to receive tokens)"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                />

                <div className="modal-hint-box">
                  <p>
                    <strong>{parsed.denomination} {getTokenDisplay()}</strong> will be sent to the recipient address.
                    The withdrawal is anonymous — no on-chain link to your deposit.
                  </p>
                </div>

                <button
                  className="btn-primary btn-amber"
                  onClick={handleWithdraw}
                  disabled={!recipient.trim()}
                >
                  Withdraw →
                </button>
              </>
            )}
          </div>
        )}

        {/* Withdrawing */}
        {step === "withdrawing" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">Withdrawing {parsed?.denomination} {getTokenDisplay()}...</p>
            <p className="status-sub">Confirm in MetaMask</p>
          </div>
        )}

        {/* Success */}
        {step === "success" && parsed && (
          <div className="modal-section center">
            <div className="success-banner">✓ Withdrawal Successful!</div>
            <p className="status-sub">
              {parsed.denomination} {getTokenDisplay()} sent to <strong>{recipient.slice(0, 10)}...</strong>
            </p>
            {txHash && (
              <a
                className="tx-link"
                href={`https://sepolia.etherscan.io/tx/${txHash}`}
                target="_blank"
                rel="noreferrer"
              >
                View on Etherscan ↗
              </a>
            )}
            <button className="btn-primary" onClick={onClose}>Close</button>
          </div>
        )}

        {/* Error */}
        {step === "error" && (
          <div className="modal-section center">
            <div className="error-banner">✗ Failed</div>
            <p className="error-msg">{error}</p>
            <button className="btn-primary" onClick={() => setStep("parsed")}>
              Try Again
            </button>
          </div>
        )}
      </div>
    </div>
  );
}