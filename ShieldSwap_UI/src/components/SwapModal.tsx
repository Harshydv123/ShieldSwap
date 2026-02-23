import React, { useState, useEffect } from "react";
import { ethers } from "ethers";
import { useWalletClient } from "wagmi";
import { ADDRESSES, SSROUTER_ABI, SSPAIR_ABI, ERC20_ABI } from "../constants";

type Step = "idle" | "approving" | "swapping" | "success" | "error";
type Direction = "AtoB" | "BtoA";

interface Props {
  onClose: () => void;
}

export default function SwapModal({ onClose }: Props) {
  const { data: walletClient } = useWalletClient();

  const [step, setStep] = useState<Step>("idle");
  const [direction, setDirection] = useState<Direction>("AtoB");
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");
  const [isCalculating, setIsCalculating] = useState(false);

  // Calculate expected output amount
  useEffect(() => {
    if (!amountIn || parseFloat(amountIn) <= 0) {
      setAmountOut(null);
      return;
    }

    const calculateOutput = async () => {
      try {
        setIsCalculating(true);
        const provider = new ethers.JsonRpcProvider("https://eth-sepolia.g.alchemy.com/v2/ME1F65j3LyUJCGulX4gJS");
        
        const router = new ethers.Contract(ADDRESSES.SSRouter, SSROUTER_ABI, provider);
        const pair = new ethers.Contract(ADDRESSES.SSPair, SSPAIR_ABI, provider);
        
        // Get reserves
        const [r0, r1] = await pair.getReserves();
        const token0 = await pair.token0();
        
        const isAToken0 = token0.toLowerCase() === ADDRESSES.TokenA.toLowerCase();
        const reserveIn = direction === "AtoB" ? (isAToken0 ? r0 : r1) : (isAToken0 ? r1 : r0);
        const reserveOut = direction === "AtoB" ? (isAToken0 ? r1 : r0) : (isAToken0 ? r0 : r1);
        
        // Calculate output using router's getAmountOut
        const amountInWei = ethers.parseUnits(amountIn, 18);
        const output = await router.getAmountOut(amountInWei, reserveIn, reserveOut);
        
        setAmountOut(ethers.formatUnits(output, 18));
        setIsCalculating(false);
      } catch (e) {
        console.error("Failed to calculate output:", e);
        setAmountOut(null);
        setIsCalculating(false);
      }
    };

    const debounce = setTimeout(calculateOutput, 500);
    return () => clearTimeout(debounce);
  }, [amountIn, direction]);

  const handleSwap = async () => {
    if (!walletClient || !amountIn || !amountOut) return;
    
    const amountInNum = parseFloat(amountIn);
    if (isNaN(amountInNum) || amountInNum <= 0) {
      setError("Enter a valid amount");
      return;
    }

    try {
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();
      const address = await signer.getAddress();

      const amountInWei = ethers.parseUnits(amountIn, 18);
      const amountOutWei = ethers.parseUnits(amountOut, 18);
      
      // 0.5% slippage tolerance
      const minAmountOut = (amountOutWei * 995n) / 1000n;

      const tokenIn = direction === "AtoB" ? ADDRESSES.TokenA : ADDRESSES.TokenB;
      const tokenOut = direction === "AtoB" ? ADDRESSES.TokenB : ADDRESSES.TokenA;

      // Step 1: Approve
      setStep("approving");
      const tokenContract = new ethers.Contract(tokenIn, ERC20_ABI, signer);
      const approveTx = await tokenContract.approve(ADDRESSES.SSRouter, amountInWei);
      await approveTx.wait();

      // Step 2: Swap
      setStep("swapping");
      const router = new ethers.Contract(ADDRESSES.SSRouter, SSROUTER_ABI, signer);
      const swapTx = await router.swapExactTokensForTokens(
        tokenIn,
        tokenOut,
        amountInWei,
        minAmountOut,
        address
      );
      const receipt = await swapTx.wait();
      setTxHash(receipt.hash);
      setStep("success");

      // Trigger balance update
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      setError(e?.reason || e?.message || "Swap failed");
      setStep("error");
    }
  };

  const flipDirection = () => {
    setDirection(direction === "AtoB" ? "BtoA" : "AtoB");
    setAmountIn("");
    setAmountOut(null);
  };

  const tokenInSymbol = direction === "AtoB" ? "TokenA (Mock ETH)" : "TokenB (Mock BTC)";
  const tokenOutSymbol = direction === "AtoB" ? "TokenB (Mock BTC)" : "TokenA (Mock ETH)";

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close" onClick={onClose}>✕</button>

        <div className="modal-header">
          <span className="modal-icon">🔄</span>
          <h2>Swap Tokens</h2>
          <p className="modal-sub">Public swap for arbitrage opportunities</p>
        </div>

        {/* Idle State - Swap Interface */}
        {step === "idle" && (
          <div className="modal-section">
            {/* Input Token */}
            <div className="swap-box">
              <div className="swap-box-header">
                <span className="swap-label">You Pay</span>
                <span className="swap-token">{tokenInSymbol}</span>
              </div>
              <input
                className="swap-input"
                type="number"
                min="0"
                step="any"
                placeholder="0.0"
                value={amountIn}
                onChange={(e) => { setAmountIn(e.target.value); setError(""); }}
              />
            </div>

            {/* Flip Button */}
            <div className="swap-flip-container">
              <button className="swap-flip-btn" onClick={flipDirection} title="Flip direction">
                ⇅
              </button>
            </div>

            {/* Output Token */}
            <div className="swap-box">
              <div className="swap-box-header">
                <span className="swap-label">You Receive</span>
                <span className="swap-token">{tokenOutSymbol}</span>
              </div>
              <div className="swap-output">
                {isCalculating ? (
                  <span className="swap-calculating">Calculating...</span>
                ) : amountOut ? (
                  <span className="swap-output-value">
                    {parseFloat(amountOut).toFixed(6)}
                  </span>
                ) : (
                  <span className="swap-output-placeholder">0.0</span>
                )}
              </div>
            </div>

            {/* Price Impact Info */}
            {amountOut && (
              <div className="swap-info-box">
                <div className="swap-info-row">
                  <span className="swap-info-label">Rate:</span>
                  <span className="swap-info-value">
                    1 {direction === "AtoB" ? "TokenA" : "TokenB"} ≈{" "}
                    {(parseFloat(amountOut) / parseFloat(amountIn)).toFixed(6)}{" "}
                    {direction === "AtoB" ? "TokenB" : "TokenA"}
                  </span>
                </div>
                <div className="swap-info-row">
                  <span className="swap-info-label">Slippage Tolerance:</span>
                  <span className="swap-info-value">0.5%</span>
                </div>
              </div>
            )}

            {error && <div className="error-inline">{error}</div>}

            <button
              className="btn-primary btn-swap"
              onClick={handleSwap}
              disabled={!amountIn || !amountOut || parseFloat(amountIn) <= 0}
            >
              Swap →
            </button>
          </div>
        )}

        {/* Approving */}
        {step === "approving" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">Approving {tokenInSymbol}...</p>
            <p className="status-sub">Confirm in MetaMask (1 of 2)</p>
          </div>
        )}

        {/* Swapping */}
        {step === "swapping" && (
          <div className="modal-section center">
            <div className="spinner" />
            <p className="status-text">Executing swap...</p>
            <p className="status-sub">Confirm in MetaMask (2 of 2)</p>
          </div>
        )}

        {/* Success */}
        {step === "success" && (
          <div className="modal-section center">
            <div className="success-banner">✓ Swap Successful!</div>
            <p className="status-sub">
              Swapped {parseFloat(amountIn).toFixed(4)} {tokenInSymbol.split(" ")[0]} for{" "}
              {amountOut && parseFloat(amountOut).toFixed(4)} {tokenOutSymbol.split(" ")[0]}
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
            <div className="error-banner">✗ Swap Failed</div>
            <p className="error-msg">{error}</p>
            <button className="btn-primary" onClick={() => setStep("idle")}>
              Try Again
            </button>
          </div>
        )}
      </div>

      <style>{`
        /* Swap-specific styles */
        .swap-box {
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 12px;
          padding: 1rem;
        }

        .swap-box-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }

        .swap-label {
          font-size: 0.8rem;
          color: #64748b;
          font-weight: 500;
        }

        .swap-token {
          font-size: 0.85rem;
          color: #00d2c8;
          font-weight: 600;
        }

        .swap-input {
          width: 100%;
          background: transparent;
          border: none;
          font-size: 2rem;
          font-weight: 700;
          color: #fff;
          outline: none;
          padding: 0;
        }

        .swap-input::placeholder {
          color: rgba(255,255,255,0.2);
        }

        .swap-output {
          font-size: 2rem;
          font-weight: 700;
          color: #00d2c8;
          min-height: 48px;
          display: flex;
          align-items: center;
        }

        .swap-output-placeholder {
          color: rgba(255,255,255,0.2);
        }

        .swap-calculating {
          font-size: 0.9rem;
          color: #64748b;
          font-weight: 500;
        }

        .swap-flip-container {
          display: flex;
          justify-content: center;
          margin: -0.75rem 0;
          position: relative;
          z-index: 10;
        }

        .swap-flip-btn {
          background: rgba(0,210,200,0.15);
          border: 2px solid #00d2c8;
          color: #00d2c8;
          width: 40px;
          height: 40px;
          border-radius: 50%;
          cursor: pointer;
          font-size: 1.2rem;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: all 0.2s;
        }

        .swap-flip-btn:hover {
          background: rgba(0,210,200,0.25);
          transform: rotate(180deg);
        }

        .swap-info-box {
          background: rgba(0,210,200,0.05);
          border: 1px solid rgba(0,210,200,0.15);
          border-radius: 8px;
          padding: 0.75rem 1rem;
          margin-top: 1rem;
        }

        .swap-info-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 0.25rem 0;
        }

        .swap-info-label {
          font-size: 0.8rem;
          color: #64748b;
        }

        .swap-info-value {
          font-size: 0.8rem;
          color: #00d2c8;
          font-weight: 600;
        }

        .btn-swap {
          background: rgba(0,210,200,0.15);
          border-color: #00d2c8;
          color: #00d2c8;
        }

        .btn-swap:hover:not(:disabled) {
          background: rgba(0,210,200,0.25);
        }

        .btn-swap:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }
      `}</style>
    </div>
  );
}