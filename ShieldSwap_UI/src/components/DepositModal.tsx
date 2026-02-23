import React, { useState } from "react";
import { ethers } from "ethers";
import { useWalletClient } from "wagmi";
import { ADDRESSES, DENOMINATIONS, SHIELD_POOL_ABI, ERC20_ABI } from "../constants";
import { generateNote } from "../utils";

type Step = "idle" | "generated" | "approving" | "depositing" | "success" | "error";
type Token = "TokenA" | "TokenB";
type Denomination = "100" | "10" | "1";

interface Props {
  onClose: () => void;
}

export default function DepositModal({ onClose }: Props) {
  const { data: walletClient } = useWalletClient();

  const [step, setStep] = useState<Step>("idle");
  const [selectedToken, setSelectedToken] = useState<Token>("TokenA");
  const [selectedDenomination, setSelectedDenomination] = useState<Denomination>("100");
  const [noteData, setNoteData] = useState<{ nullifier: string; secret: string; commitment: string; noteString: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");

  
  const availableDenominations: Denomination[] = 
    selectedToken === "TokenA" ? ["100", "10"] : ["10", "1"];

  React.useEffect(() => {
    if (!availableDenominations.includes(selectedDenomination)) {
      setSelectedDenomination(availableDenominations[0]);
    }
  }, [selectedToken]);

  // Get the pool address based on selection
  const getPoolAddress = () => {
    const key = `${selectedToken}_${selectedDenomination}` as keyof typeof ADDRESSES.ShieldPools;
    return ADDRESSES.ShieldPools[key];
  };

  // Get the denomination amount
  const getDenominationAmount = () => {
    const key = `${selectedToken}_${selectedDenomination}` as keyof typeof DENOMINATIONS;
    return DENOMINATIONS[key];
  };

  // Get token address
  const getTokenAddress = () => {
    return selectedToken === "TokenA" ? ADDRESSES.TokenA : ADDRESSES.TokenB;
  };

  const handleGenerate = async () => {
    try {
      const note = await generateNote(selectedToken, selectedDenomination);
      setNoteData(note);
      setStep("generated");
      setError("");
    } catch (e: any) {
      setError("Failed to generate note: " + (e?.message || String(e)));
      setStep("error");
    }
  };

  const handleDeposit = async () => {
    if (!walletClient || !noteData) return;
    try {
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();

      const poolAddress = getPoolAddress();
      const tokenAddress = getTokenAddress();
      const amount = getDenominationAmount();

      // Step 1: Approve
      setStep("approving");
      const token = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
      const approveTx = await token.approve(poolAddress, amount);
      await approveTx.wait();

      // Step 2: Deposit
      setStep("depositing");
      const pool = new ethers.Contract(poolAddress, SHIELD_POOL_ABI, signer);
      const depositTx = await pool.deposit(noteData.commitment);
      const receipt = await depositTx.wait();
      setTxHash(receipt.hash);
      setStep("success");
      
      // Trigger balance update
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      setError(e?.message || "Transaction failed");
      setStep("error");
    }
  };

  const copyNote = () => {
    if (!noteData) return;
    navigator.clipboard.writeText(noteData.noteString);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const tokenDisplay = selectedToken === "TokenA" ? "Mock ETH" : "Mock BTC";

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close" onClick={onClose}>✕</button>

        <div className="modal-header">
          <span className="modal-icon">🔒</span>
          <h2>Deposit</h2>
          <p className="modal-sub">Anonymous deposit into the ZK shield pool</p>
        </div>

        {/* Step 1: Token & Denomination Selection */}
        {step === "idle" && (
          <div className="modal-section">
            <label className="input-label">Select Token</label>
            <div className="token-selection">
              <button
                className={`token-btn ${selectedToken === "TokenA" ? "token-btn-active" : ""}`}
                onClick={() => setSelectedToken("TokenA")}
              >
                <div className="token-btn-icon">Ξ</div>
                <div className="token-btn-label">TokenA</div>
                <div className="token-btn-sub">Mock ETH</div>
              </button>
              <button
                className={`token-btn ${selectedToken === "TokenB" ? "token-btn-active" : ""}`}
                onClick={() => setSelectedToken("TokenB")}
              >
                <div className="token-btn-icon">₿</div>
                <div className="token-btn-label">TokenB</div>
                <div className="token-btn-sub">Mock BTC</div>
              </button>
            </div>

            <label className="input-label" style={{ marginTop: "1rem" }}>Select Denomination</label>
            <div className="denomination-selection">
              {availableDenominations.map((denom) => (
                <button
                  key={denom}
                  className={`denom-btn ${selectedDenomination === denom ? "denom-btn-active" : ""}`}
                  onClick={() => setSelectedDenomination(denom)}
                >
                  {denom} {tokenDisplay}
                </button>
              ))}
            </div>

            <div className="modal-amount-badge" style={{ marginTop: "1rem" }}>
              You will deposit: <strong>{selectedDenomination} {tokenDisplay}</strong>
            </div>

            <p className="modal-hint">Generate a cryptographic note. <strong>Save it</strong> — it's your only way to withdraw.</p>
            
            {error && <div className="error-inline">{error}</div>}
            
            <button className="btn-primary" onClick={handleGenerate}>
              Generate Note →
            </button>
          </div>
        )}

        {/* Step 2: Show note + approve/deposit */}
        {step === "generated" && noteData && (
          <div className="modal-section">
            <div className="note-box">
              <div className="note-label">Your Shielded Note</div>
              <div className="note-value">{noteData.noteString}</div>
              <button className="btn-copy" onClick={copyNote}>
                {copied ? "✓ Copied!" : "Copy Note"}
              </button>
            </div>
            <div className="warning-box">
              ⚠️ <strong>SAVE THIS NOTE!</strong> It cannot be recovered. Store it somewhere safe offline. Anyone with this note can withdraw your funds.
            </div>
            <div className="commitment-preview">
              <span className="label-small">Commitment:</span>
              <span className="mono-small">{noteData.commitment.slice(0, 20)}...{noteData.commitment.slice(-8)}</span>
            </div>
            <button className="btn-primary btn-green" onClick={handleDeposit}>
              Approve &amp; Deposit →
            </button>
          </div>
        )}

        {/* Approving */}
        {step === "approving" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">Step 1/2 — Approving {selectedDenomination} {tokenDisplay}...</p>
            <p className="status-sub">Confirm in MetaMask</p>
          </div>
        )}

        {/* Depositing */}
        {step === "depositing" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">Step 2/2 — Depositing to ShieldPool...</p>
            <p className="status-sub">Confirm in MetaMask</p>
          </div>
        )}

        {/* Success */}
        {step === "success" && noteData && (
          <div className="modal-section">
            <div className="success-banner">✓ Deposit Successful!</div>
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
            <div className="note-box">
              <div className="note-label">🔑 Your Withdrawal Note</div>
              <div className="note-value">{noteData.noteString}</div>
              <button className="btn-copy" onClick={copyNote}>
                {copied ? "✓ Copied!" : "Copy Note"}
              </button>
            </div>
            <div className="warning-box warning-red">
              ⛔ <strong>LAST CHANCE TO SAVE YOUR NOTE!</strong><br />
              Without this note you <em>cannot</em> withdraw your funds. There is no recovery option.
            </div>
            <button className="btn-primary" onClick={onClose}>Close</button>
          </div>
        )}

        {/* Error */}
        {step === "error" && (
          <div className="modal-section center">
            <div className="error-banner">✗ Transaction Failed</div>
            <p className="error-msg">{error}</p>
            <button className="btn-primary" onClick={() => setStep(noteData ? "generated" : "idle")}>
              Try Again
            </button>
          </div>
        )}

        <style>{`
          .token-selection {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 0.75rem;
          }

          .token-btn {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 0.4rem;
            padding: 1rem;
            border-radius: 8px;
            border: 1.5px solid rgba(255,255,255,0.12);
            background: rgba(255,255,255,0.04);
            cursor: pointer;
            transition: all 0.2s;
          }

          .token-btn:hover {
            border-color: rgba(0,210,200,0.4);
            background: rgba(0,210,200,0.08);
          }

          .token-btn-active {
            border-color: #00d2c8;
            background: rgba(0,210,200,0.15);
          }

          .token-btn-icon {
            font-size: 2rem;
          }

          .token-btn-label {
            font-size: 0.9rem;
            font-weight: 600;
            color: #e2e8f0;
          }

          .token-btn-sub {
            font-size: 0.75rem;
            color: #64748b;
          }

          .denomination-selection {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 0.75rem;
          }

          .denom-btn {
            padding: 0.75rem;
            border-radius: 8px;
            border: 1.5px solid rgba(255,255,255,0.12);
            background: rgba(255,255,255,0.04);
            color: #e2e8f0;
            font-size: 0.9rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
          }

          .denom-btn:hover {
            border-color: rgba(0,210,200,0.4);
            background: rgba(0,210,200,0.08);
          }

          .denom-btn-active {
            border-color: #00d2c8;
            background: rgba(0,210,200,0.15);
            color: #00d2c8;
          }
        `}</style>
      </div>
    </div>
  );
}