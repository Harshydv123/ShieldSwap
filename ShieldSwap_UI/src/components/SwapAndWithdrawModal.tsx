import React, { useState, useRef, useEffect, useCallback } from "react";
import { ethers } from "ethers";
import { useWalletClient } from "wagmi";
import {
  ADDRESSES,
  SHIELD_POOL_ABI,
  CHAINLINK_ABI,
  SSPAIR_ABI,
  OPENAI_API_KEY,
} from "../constants";
import { parseNote, makeZeroProof, now } from "../utils";

type Step = "idle" | "parsed" | "monitoring" | "executing" | "success" | "error";

interface LogLine {
  time: string;
  text: string;
  type: "info" | "ai" | "action" | "warn" | "success";
}

interface Props {
  onClose: () => void;
}

const ALCHEMY_RPC = "https://eth-sepolia.g.alchemy.com/v2/nQxCPAGNNIREyBxHf5jHf3lXnJmSwx38";

export default function SwapAndWithdrawModal({ onClose }: Props) {
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
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");
  const [lastConfidence, setLastConfidence] = useState<number | null>(null);
  const [deviationThreshold, setDeviationThreshold] = useState("5");
  const thresholdRef = useRef(deviationThreshold);

  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const logsEndRef = useRef<HTMLDivElement>(null);
  const isRunning = useRef(false);

  const addLog = useCallback((text: string, type: LogLine["type"] = "info") => {
    setLogs((prev) => [...prev.slice(-80), { time: now(), text, type }]);
  }, []);

  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      isRunning.current = false;
    };
  }, []);

  useEffect(() => {
    thresholdRef.current = deviationThreshold;
  }, [deviationThreshold]);

  const handleParse = () => {
    try {
      const result = parseNote(noteInput);
      setParsed(result);
      setStep("parsed");
      setError("");
    } catch (e: any) {
      setError(e.message || "Invalid note");
    }
  };

  const fetchChainlinkPrice = async (provider: ethers.AbstractProvider, feedAddress: string): Promise<number> => {
    const feed = new ethers.Contract(feedAddress, CHAINLINK_ABI, provider);
    const [, answer] = await feed.latestRoundData();
    return Number(answer) / 1e8;
  };

  const fetchReserves = async (provider: ethers.AbstractProvider): Promise<{ r0: number; r1: number; token0: string }> => {
    const pair = new ethers.Contract(ADDRESSES.SSPair, SSPAIR_ABI, provider);
    const [r0, r1] = await pair.getReserves();
    const token0 = await pair.token0();
    return {
      r0: Number(ethers.formatUnits(r0, 18)),
      r1: Number(ethers.formatUnits(r1, 18)),
      token0,
    };
  };

  const askOpenAI = async (
    inputToken: "TokenA" | "TokenB",
    poolPrice: number,
    marketPrice: number,
    deviation: number
  ): Promise<{ decision: "SWAP" | "WAIT"; confidence: number; reason: string }> => {
    
    const inputName = inputToken === "TokenA" ? "MockETH" : "MockBTC";
    const outputName = inputToken === "TokenA" ? "MockBTC" : "MockETH";
    const priceUnit = inputToken === "TokenA" 
      ? "MockBTC per MockETH" 
      : "MockETH per MockBTC";

    const prompt = `You are a DeFi trading AI for ShieldSwap, a privacy AMM on Ethereum Sepolia testnet.

User deposited: ${inputName}
Swapping to: ${outputName}

Pool price (${priceUnit}): ${poolPrice.toFixed(4)}
Market price (real ${priceUnit} via Chainlink): ${marketPrice.toFixed(4)}
Price deviation: ${deviation > 0 ? "+" : ""}${(deviation * 100).toFixed(2)}%

${inputToken === "TokenA" 
  ? "A positive deviation means the pool gives MORE MockBTC per MockETH than the market — favorable to swap."
  : "A positive deviation means the pool gives MORE MockETH per MockBTC than the market — favorable to swap."}

Should we execute the private swap now?
Rules:
- SWAP if deviation is positive (>2%) AND conditions are stable
- WAIT if deviation is negative, near zero, or data seems unreliable

Respond ONLY with valid JSON (no markdown):
{"decision":"SWAP","confidence":87,"reason":"Pool overvalues output token, good exit opportunity"}
or
{"decision":"WAIT","confidence":91,"reason":"Deviation unfavorable, wait for better rate"}`;

    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 120,
        temperature: 0.2,
      }),
    });

    const data = await res.json();
    const text = data.choices?.[0]?.message?.content || "";
    try {
      const cleaned = text.replace(/```json|```/g, "").trim();
      return JSON.parse(cleaned);
    } catch {
      return { decision: "WAIT", confidence: 50, reason: "Parse error - defaulting to WAIT" };
    }
  };

  const executeSwapWithdraw = async () => {
    if (!walletClient || !parsed) return;
    try {
      setStep("executing");
      addLog("CONDITIONS MET → Executing swap & withdraw...", "action");

      const provider = new ethers.BrowserProvider(walletClient.transport, "any");
      const signer = await provider.getSigner();

      // Get correct pool address based on parsed note
      const poolKey = `${parsed.token}_${parsed.denomination}` as keyof typeof ADDRESSES.ShieldPools;
      const poolAddress = ADDRESSES.ShieldPools[poolKey];

      // Determine output token (opposite of input)
      const outputToken = parsed.token === "TokenA" ? ADDRESSES.TokenB : ADDRESSES.TokenA;

      const pool = new ethers.Contract(poolAddress, SHIELD_POOL_ABI, signer);

      const root = await pool.getLastRoot();
      const proof = makeZeroProof();

      addLog("Submitting transaction...", "action");
      const tx = await pool.swapAndWithdraw(
        proof,
        root,
        parsed.nullifierHash,
        recipient,
        outputToken,  // Dynamic based on input token
        0,
        ethers.ZeroAddress,
        0
      );
      addLog(`Tx submitted: ${tx.hash.slice(0, 18)}...`, "success");
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("success");
      addLog("✓ Swap & Withdraw complete!", "success");
      
      window.dispatchEvent(new Event('balanceUpdate'));
    } catch (e: any) {
      const msg = e?.message || "Execution failed";
      addLog(`✗ Error: ${msg.slice(0, 80)}`, "warn");
      setError(msg);
      setStep("error");
    }
  };

  const runCheck = useCallback(async () => {
    if (!isRunning.current || !walletClient || !parsed) return;
    try {
      const provider = new ethers.BrowserProvider(walletClient.transport, "any");

      addLog("Reading reserves...", "info");
      const { r0, r1, token0 } = await fetchReserves(provider);

      const isTokenAToken0 = token0.toLowerCase() === ADDRESSES.TokenA.toLowerCase();
      const reserveETH = isTokenAToken0 ? r0 : r1;  // TokenA (MockETH)
      const reserveBTC = isTokenAToken0 ? r1 : r0;  // TokenB (MockBTC)

      // Calculate pool price based on INPUT token
      let poolPrice: number;
      let priceDescription: string;
      
      if (parsed.token === "TokenA") {
        // Input = ETH, Output = BTC
        // "How much BTC do I get per 1 ETH?"
        poolPrice = reserveBTC / reserveETH;
        priceDescription = "MockBTC per MockETH";
      } else {
        // Input = BTC, Output = ETH
        // "How much ETH do I get per 1 BTC?"
        poolPrice = reserveETH / reserveBTC;
        priceDescription = "MockETH per MockBTC";
      }

      addLog(`Pool: MockETH=${reserveETH.toFixed(4)} / MockBTC=${reserveBTC.toFixed(4)}`, "info");
      addLog(`Pool price: ${poolPrice.toFixed(4)} ${priceDescription}`, "info");

      addLog("Fetching Chainlink prices...", "info");
      const ethUsd = await fetchChainlinkPrice(provider, ADDRESSES.ETH_USD);
      const btcUsd = await fetchChainlinkPrice(provider, ADDRESSES.BTC_USD);

      // Calculate market price based on INPUT token
      let marketPrice: number;
      
      if (parsed.token === "TokenA") {
        // Input = ETH, Output = BTC
        marketPrice = ethUsd / btcUsd;  // BTC per ETH
      } else {
        // Input = BTC, Output = ETH
        marketPrice = btcUsd / ethUsd;  // ETH per BTC
      }

      addLog(`ETH/USD: $${ethUsd.toFixed(2)} | BTC/USD: $${btcUsd.toFixed(2)}`, "info");
      addLog(`Market: ${marketPrice.toFixed(4)} | Pool: ${poolPrice.toFixed(4)}`, "info");

      // Deviation calculation (same for both directions now that prices are normalized)
      const deviation = (poolPrice - marketPrice) / marketPrice;
      const deviationPct = deviation * 100;
      
      const inputName = parsed.token === "TokenA" ? "MockETH" : "MockBTC";
      const outputName = parsed.token === "TokenA" ? "MockBTC" : "MockETH";
      
      addLog(`Deviation: ${deviation > 0 ? "+" : ""}${deviationPct.toFixed(2)}%`, "info");
      addLog(`Input: ${inputName} → Output: ${outputName}`, "info");

      // Sanity guard
      if (Math.abs(deviationPct) > 500) {
        addLog(`⚠ Deviation too extreme (${deviationPct.toFixed(0)}%) — pool may be illiquid`, "warn");
        addLog("Skipping AI consultation. Next check in 30s...", "info");
        return;
      }

      addLog("Consulting AI...", "ai");
      const { decision, confidence, reason } = await askOpenAI(parsed.token, poolPrice, marketPrice, deviation);
      setLastConfidence(confidence);

      const thresholdValue = parseFloat(thresholdRef.current) || 5;
      
      // CRITICAL: For both directions, positive deviation is good!
      // Because we normalized the pool and market prices to be in terms of "output per input"
      if (decision === "SWAP" && confidence >= 80 && deviationPct > -thresholdValue) {
        addLog(`AI: SWAP (${confidence}% confidence) — ${reason}`, "ai");
        addLog(`✓ Deviation ${deviationPct.toFixed(2)}% exceeds threshold of -${thresholdValue}%`, "success");
        if (intervalRef.current) clearInterval(intervalRef.current);
        isRunning.current = false;
        await executeSwapWithdraw();
      } else {
        addLog(`AI: WAIT (${confidence}% confidence) — ${reason}`, "ai");
        if (deviationPct <= -thresholdValue) {
          addLog(`Deviation ${deviationPct.toFixed(2)}% is below threshold (-${thresholdValue}%)`, "info");
        }
        addLog("Next check in 30s...", "info");
      }
    } catch (e: any) {
      addLog(`Error during check: ${(e?.message || "unknown").slice(0, 60)}`, "warn");
      addLog("Retrying in 30s...", "info");
    }
  }, [parsed, recipient, addLog, walletClient]);

  const startMonitoring = () => {
    if (!ethers.isAddress(recipient)) {
      setError("Invalid recipient address");
      return;
    }
    setLogs([]);
    setStep("monitoring");
    isRunning.current = true;
    addLog("CRE monitoring started", "success");
    runCheck();
    intervalRef.current = setInterval(runCheck, 30_000);
  };

  const stopMonitoring = () => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    isRunning.current = false;
    setStep("parsed");
    addLog("Monitoring stopped by user.", "warn");
  };

  const logColor = (type: LogLine["type"]) => {
    switch (type) {
      case "ai": return "#a855f7";
      case "action": return "#f59e0b";
      case "warn": return "#ef4444";
      case "success": return "#22c55e";
      default: return "#22d3ee";
    }
  };

  const getTokenDisplay = () => {
    if (!parsed) return { input: "Token", output: "Token" };
    return {
      input: parsed.token === "TokenA" ? "Mock ETH" : "Mock BTC",
      output: parsed.token === "TokenA" ? "Mock BTC" : "Mock ETH",
    };
  };

  const tokenDisplay = getTokenDisplay();

  return (
    <div className="modal-overlay" onClick={step === "monitoring" ? undefined : onClose}>
      <div className="modal-box modal-box-wide" onClick={(e) => e.stopPropagation()}>
        {step !== "monitoring" && step !== "executing" && (
          <button className="modal-close" onClick={onClose}>✕</button>
        )}

        <div className="modal-header">
          <span className="modal-icon">⚡</span>
          <h2>Swap &amp; Withdraw</h2>
          <p className="modal-sub">AI-powered CRE monitors every 30s for optimal swap timing</p>
        </div>

        {/* Input phase */}
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
                    <span className="label-small">Deposited:</span>
                    <span className="mono-small">{parsed.denomination} {tokenDisplay.input}</span>
                  </div>
                  <div className="parsed-row">
                    <span className="label-small">Will swap to:</span>
                    <span className="mono-small">{tokenDisplay.output}</span>
                  </div>
                  <div className="parsed-row">
                    <span className="label-small">Commitment:</span>
                    <span className="mono-small">{parsed.commitment.slice(0, 16)}...{parsed.commitment.slice(-6)}</span>
                  </div>
                </div>

                <label className="input-label" style={{ marginTop: "1rem" }}>Recipient Address</label>
                <input
                  className="modal-input"
                  placeholder={`0x... (address to receive ${tokenDisplay.output})`}
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                />

                <label className="input-label" style={{ marginTop: "1rem" }}>
                  Deviation Threshold (%)
                  <span style={{ fontSize: "0.75rem", color: "#64748b", marginLeft: "0.5rem" }}>
                    AI will swap when deviation {">"} -X%
                  </span>
                </label>
                <input
                  className="modal-input"
                  type="number"
                  min="0"
                  max="50"
                  step="0.1"
                  placeholder="e.g., 5"
                  value={deviationThreshold}
                  onChange={(e) => setDeviationThreshold(e.target.value)}
                />
                <div className="modal-hint-box">
                  <p>
                    <strong>Example:</strong> If you set <strong>5%</strong>, the AI will execute when 
                    pool deviation is greater than <strong>-5%</strong> (i.e., -4%, 0%, +2%, etc.).
                    <br/><br/>
                    Lower = More strict, wait for better rates<br/>
                    Higher = More lenient, swap sooner
                  </p>
                </div>

                <button
                  className="btn-primary btn-purple"
                  onClick={startMonitoring}
                  disabled={!recipient.trim()}
                >
                  Start Monitoring →
                </button>
              </>
            )}
          </div>
        )}

        {/* Terminal / monitoring phase */}
        {(step === "monitoring" || step === "executing") && (
          <div className="modal-section">
            <div className="terminal-header">
              <span className="terminal-dot red" />
              <span className="terminal-dot yellow" />
              <span className="terminal-dot green" />
              <span className="terminal-title">CRE TERMINAL</span>
              {lastConfidence !== null && (
                <span className="terminal-confidence">AI: {lastConfidence}%</span>
              )}
            </div>
            <div className="terminal-body">
              {logs.map((log, i) => (
                <div key={i} className="terminal-line">
                  <span className="terminal-time">[{log.time}]</span>{" "}
                  <span style={{ color: logColor(log.type) }}>{log.text}</span>
                </div>
              ))}
              <div ref={logsEndRef} />
              {step === "monitoring" && (
                <div className="terminal-cursor">█</div>
              )}
            </div>
            {step === "monitoring" && (
              <button className="btn-danger" onClick={stopMonitoring}>
                ⏹ Stop Monitoring
              </button>
            )}
            {step === "executing" && (
              <div className="modal-section center">
                <div className="spinner" />
                <p className="status-text">Executing... Confirm in MetaMask</p>
              </div>
            )}
          </div>
        )}

        {/* Success */}
        {step === "success" && parsed && (
          <div className="modal-section center">
            <div className="success-banner">✓ Swap &amp; Withdraw Complete!</div>
            <p className="status-sub">{tokenDisplay.output} sent to <strong>{recipient.slice(0, 10)}...</strong></p>
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
            <div className="error-banner">✗ Execution Failed</div>
            <p className="error-msg">{error}</p>
            <button className="btn-primary" onClick={() => setStep("parsed")}>Try Again</button>
          </div>
        )}
      </div>
    </div>
  );
}