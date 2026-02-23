import React, { useState, useEffect } from "react";
import { ethers } from "ethers";
import { useWalletClient } from "wagmi";
import { ADDRESSES, SSROUTER_ABI, SSPAIR_ABI, ERC20_ABI } from "../constants";

type Tab = "mint" | "burn";
type Step = "idle" | "approveA" | "approveB" | "approveLP" | "transacting" | "success" | "error";

interface Props {
  onClose: () => void;
}

const SEPOLIA_RPC = "https://eth-sepolia.g.alchemy.com/v2/nQxCPAGNNIREyBxHf5jHf3lXnJmSwx38"; // used for LP balance reads

export default function LiquidityModal({ onClose }: Props) {
  const { data: walletClient } = useWalletClient();

  const [tab, setTab] = useState<Tab>("mint");
  const [step, setStep] = useState<Step>("idle");
  const [statusMsg, setStatusMsg] = useState("");
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");
  const [lpBalance, setLpBalance] = useState<string | null>(null);

  // Mint inputs
  const [amountA, setAmountA] = useState("");
  const [amountB, setAmountB] = useState("");

  // Burn inputs
  const [lpAmount, setLpAmount] = useState("");

  // Fetch LP balance when switching to burn tab
  useEffect(() => {
    if (tab !== "burn" || !walletClient) return;
    const fetchLpBal = async () => {
      try {
        const provider = new ethers.BrowserProvider(walletClient.transport, "any");
        const signer = await provider.getSigner();
        const address = await signer.getAddress();
        const pair = new ethers.Contract(ADDRESSES.SSPair, SSPAIR_ABI, provider);
        const bal = await pair.balanceOf(address);
        setLpBalance(ethers.formatUnits(bal, 18));
      } catch {
        setLpBalance(null);
      }
    };
    fetchLpBal();
  }, [tab, walletClient]);

  const reset = () => {
    setStep("idle");
    setError("");
    setTxHash("");
    setStatusMsg("");
  };

  const handleMint = async () => {
    if (!walletClient) return;

    // ── Validate inputs ──────────────────────────────────────────────────
    const aNum = parseFloat(amountA);
    const bNum = parseFloat(amountB);
    if (!amountA || isNaN(aNum) || aNum <= 0) {
      setError("Enter a valid TokenA (Mock ETH) amount greater than 0");
      return;
    }
    if (!amountB || isNaN(bNum) || bNum <= 0) {
      setError("Enter a valid TokenB (Mock BTC) amount greater than 0");
      return;
    }
    setError("");

    try {
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();
      const address = await signer.getAddress();

      const amtA = ethers.parseUnits(amountA, 18);
      const amtB = ethers.parseUnits(amountB, 18);

      // ── Step 1: Approve TokenA ───────────────────────────────────────
      setStep("approveA");
      setStatusMsg("Step 1/3 — Approving TokenA (Mock ETH)...");
      const tokenA = new ethers.Contract(ADDRESSES.TokenA, ERC20_ABI, signer);
      const approveTxA = await tokenA.approve(ADDRESSES.SSRouter, amtA);
      await approveTxA.wait();

      // ── Step 2: Approve TokenB ───────────────────────────────────────
      setStep("approveB");
      setStatusMsg("Step 2/3 — Approving TokenB (Mock BTC)...");
      const tokenB = new ethers.Contract(ADDRESSES.TokenB, ERC20_ABI, signer);
      const approveTxB = await tokenB.approve(ADDRESSES.SSRouter, amtB);
      await approveTxB.wait();

      // ── Step 3: Add Liquidity ────────────────────────────────────────
      // Use amountMin = 0 to handle both empty pool (first deposit) and
      // existing pool. The router will use optimal amounts automatically.
      setStep("transacting");
      setStatusMsg("Step 3/3 — Adding liquidity...");
      const router = new ethers.Contract(ADDRESSES.SSRouter, SSROUTER_ABI, signer);

      const tx = await router.addLiquidity(
        ADDRESSES.TokenA,   // tokenA
        ADDRESSES.TokenB,   // tokenB
        amtA,               // amountADesired
        amtB,               // amountBDesired
        0n,                 // amountAMin — 0 to avoid slippage revert on new pools
        0n,                 // amountBMin — 0 to avoid slippage revert on new pools
        address             // to (receive LP tokens)
      );
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("success");
      
      // Trigger balance update in parent App  
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      const msg = e?.reason || e?.message || "Transaction failed";
      setError(msg);
      setStep("error");
    }
  };

  const handleBurn = async () => {
    if (!walletClient) return;

    const lpNum = parseFloat(lpAmount);
    if (!lpAmount || isNaN(lpNum) || lpNum <= 0) {
      setError("Enter a valid LP token amount greater than 0");
      return;
    }
    setError("");

    try {
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();
      const address = await signer.getAddress();

      const lpAmt = ethers.parseUnits(lpAmount, 18);

      // ── Step 1: Approve SSRouter to transferFrom LP tokens ───────────
      // (Router internally calls pair.transferFrom(msg.sender, pair, amount))
      setStep("approveLP");
      setStatusMsg("Step 1/2 — Approving LP tokens for router...");
      const pair = new ethers.Contract(ADDRESSES.SSPair, SSPAIR_ABI, signer);
      const approveTx = await pair.approve(ADDRESSES.SSRouter, lpAmt);
      await approveTx.wait();

      // ── Step 2: Remove Liquidity ─────────────────────────────────────
      setStep("transacting");
      setStatusMsg("Step 2/2 — Burning LP tokens & withdrawing...");
      const router = new ethers.Contract(ADDRESSES.SSRouter, SSROUTER_ABI, signer);
      const tx = await router.removeLiquidity(
        ADDRESSES.TokenA,
        ADDRESSES.TokenB,
        lpAmt,
        address
      );
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("success");
      
      // Trigger balance update in parent App
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      const msg = e?.reason || e?.message || "Transaction failed";
      setError(msg);
      setStep("error");
    }
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close" onClick={onClose}>✕</button>

        <div className="modal-header">
          <span className="modal-icon">💧</span>
          <h2>Mint / Burn Liquidity</h2>
          <p className="modal-sub">Provide liquidity and earn fees from every swap</p>
        </div>

        {/* Tabs */}
        {step === "idle" && (
          <>
            <div className="tab-row">
              <button
                className={`tab-btn ${tab === "mint" ? "tab-active" : ""}`}
                onClick={() => setTab("mint")}
              >
                💧 Mint LP
              </button>
              <button
                className={`tab-btn ${tab === "burn" ? "tab-active" : ""}`}
                onClick={() => setTab("burn")}
              >
                🔥 Burn LP
              </button>
            </div>

            {tab === "mint" && (
              <div className="modal-section">
                <label className="input-label">TokenA Amount (Mock ETH)</label>
                <input
                  className="modal-input"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="e.g. 100"
                  value={amountA}
                  onChange={(e) => { setAmountA(e.target.value); setError(""); }}
                />

                <label className="input-label" style={{ marginTop: "1rem" }}>TokenB Amount (Mock BTC)</label>
                <input
                  className="modal-input"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="e.g. 2.5"
                  value={amountB}
                  onChange={(e) => { setAmountB(e.target.value); setError(""); }}
                />

                {error && <div className="error-inline">{error}</div>}

                <div className="modal-hint-box">
                  <p>Both tokens will be approved and deposited to the AMM pool. You'll receive LP tokens representing your share. Slippage is set to 0% minimum — the router will use optimal amounts.</p>
                </div>

                <button
                  className="btn-primary btn-teal"
                  onClick={handleMint}
                  disabled={!amountA || !amountB}
                >
                  Approve &amp; Add Liquidity →
                </button>
              </div>
            )}

            {tab === "burn" && (
              <div className="modal-section">
                <label className="input-label">LP Token Amount</label>
                {lpBalance !== null && (
                  <div
                    className="lp-balance-hint"
                    onClick={() => setLpAmount(lpBalance)}
                    title="Click to fill max"
                  >
                    Your LP balance: <strong>{parseFloat(lpBalance).toFixed(6)}</strong>
                    <span className="lp-max-btn">MAX</span>
                  </div>
                )}
                <input
                  className="modal-input"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="e.g. 10.5"
                  value={lpAmount}
                  onChange={(e) => { setLpAmount(e.target.value); setError(""); }}
                />

                {error && <div className="error-inline">{error}</div>}

                <div className="modal-hint-box">
                  <p>Your LP tokens will be approved and burned. You'll receive proportional TokenA and TokenB back.</p>
                </div>

                <button
                  className="btn-primary btn-teal"
                  onClick={handleBurn}
                  disabled={!lpAmount}
                >
                  Approve &amp; Remove Liquidity →
                </button>
              </div>
            )}
          </>
        )}

        {/* Approving TokenA */}
        {step === "approveA" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">{statusMsg}</p>
            <p className="status-sub">Confirm in MetaMask (1 of 3)</p>
          </div>
        )}

        {/* Approving TokenB */}
        {step === "approveB" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">{statusMsg}</p>
            <p className="status-sub">Confirm in MetaMask (2 of 3)</p>
          </div>
        )}

        {/* Approving LP */}
        {step === "approveLP" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">{statusMsg}</p>
            <p className="status-sub">Confirm in MetaMask (1 of 2)</p>
          </div>
        )}

        {/* Transacting */}
        {step === "transacting" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">{statusMsg}</p>
            <p className="status-sub">Confirm in MetaMask — final step</p>
          </div>
        )}

        {/* Success */}
        {step === "success" && (
          <div className="modal-section center">
            <div className="success-banner">
              ✓ {tab === "mint" ? "Liquidity Added!" : "Liquidity Removed!"}
            </div>
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
            <div className="error-banner">✗ Transaction Failed</div>
            <p className="error-msg">{error}</p>
            <button className="btn-primary" onClick={reset}>Try Again</button>
          </div>
        )}
      </div>
    </div>
  );
}