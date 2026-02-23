import React, { useState } from "react";
import { ethers } from "ethers";
import { useWalletClient, useAccount } from "wagmi";
import { ADDRESSES } from "../constants";

// MockToken ABI - just the mint function
const MOCK_TOKEN_ABI = [
  "function mint(address to, uint256 amount) external"
];

export default function FaucetButton() {
  const { data: walletClient } = useWalletClient();
  const { address, isConnected } = useAccount();
  
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");

  const handleClaim = async () => {
    if (!walletClient || !address) {
      setError("Please connect your wallet first");
      return;
    }

    try {
      setLoading(true);
      setError("");
      setSuccess(false);

      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();

      // Amount to mint
      const amountA = ethers.parseUnits("500", 18); // 500 TokenA
      const amountB = ethers.parseUnits("20", 18);  // 20 TokenB

      // Mint TokenA
      const tokenA = new ethers.Contract(ADDRESSES.TokenA, MOCK_TOKEN_ABI, signer);
      const txA = await tokenA.mint(address, amountA);
      await txA.wait();

      // Mint TokenB
      const tokenB = new ethers.Contract(ADDRESSES.TokenB, MOCK_TOKEN_ABI, signer);
      const txB = await tokenB.mint(address, amountB);
      await txB.wait();

      setSuccess(true);
      setLoading(false);

      // Trigger balance update
      window.dispatchEvent(new Event('balanceUpdate'));

      // Reset success message after 5 seconds
      setTimeout(() => setSuccess(false), 5000);
    } catch (e: any) {
      console.error("Faucet error:", e);
      setError(e?.reason || e?.message || "Failed to mint tokens");
      setLoading(false);
    }
  };

  if (!isConnected) {
    return null; // Don't show button if wallet not connected
  }

  return (
    <div className="faucet-container">
      <button 
        className="faucet-btn" 
        onClick={handleClaim}
        disabled={loading || success}
      >
        {loading ? "Minting..." : success ? "✓ Tokens Claimed!" : "🚰 Get Test Tokens"}
      </button>
      {error && <div className="faucet-error">{error}</div>}
      {success && (
        <div className="faucet-success">
          Claimed 500 MockETH + 20 MockBTC!
        </div>
      )}

      <style>{`
        .faucet-container {
          position: relative;
        }

        .faucet-btn {
          padding: 8px 16px;
          border-radius: 8px;
          background: rgba(34,197,94,0.15);
          border: 1.5px solid #22c55e;
          color: #22c55e;
          font-size: 0.85rem;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s;
          white-space: nowrap;
        }

        .faucet-btn:hover:not(:disabled) {
          background: rgba(34,197,94,0.25);
          transform: translateY(-1px);
        }

        .faucet-btn:disabled {
          opacity: 0.6;
          cursor: not-allowed;
          transform: none;
        }

        .faucet-error {
          position: absolute;
          top: 100%;
          right: 0;
          margin-top: 8px;
          padding: 8px 12px;
          background: rgba(239,68,68,0.12);
          border: 1px solid #ef4444;
          border-radius: 6px;
          color: #f87171;
          font-size: 0.75rem;
          white-space: nowrap;
          z-index: 10;
        }

        .faucet-success {
          position: absolute;
          top: 100%;
          right: 0;
          margin-top: 8px;
          padding: 8px 12px;
          background: rgba(34,197,94,0.15);
          border: 1px solid #22c55e;
          border-radius: 6px;
          color: #22c55e;
          font-size: 0.75rem;
          white-space: nowrap;
          z-index: 10;
          animation: slideIn 0.3s ease;
        }

        @keyframes slideIn {
          from {
            opacity: 0;
            transform: translateY(-10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>
    </div>
  );
}