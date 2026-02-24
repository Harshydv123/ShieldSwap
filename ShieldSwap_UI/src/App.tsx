import React, { useState, useEffect, useRef, useCallback } from "react";
import { ethers } from "ethers";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount } from "wagmi";
import DepositModal from "./components/DepositModal";
import WithdrawModal from "./components/WithdrawModal";
import SwapWithdrawModal from "./components/SwapWithdrawModal";
import LiquidityModal from "./components/LiquidityModal";
import FaucetButton from "./components/FaucetButton";
import SwapModal from "./components/SwapModal";
import { ADDRESSES, SSPAIR_ABI, SHIELD_POOL_ABI, CHAINLINK_ABI, ERC20_ABI } from "./constants";

const SEPOLIA_RPC = "https://eth-sepolia.g.alchemy.com/v2/ME1F65j3LyUJCGulX4gJS";

type Modal = "deposit" | "withdraw" | "swapWithdraw" | "normalSwap" | "liquidity" | null;

interface Stats {
  reserveA: string;
  reserveB: string;
}

interface UserBalances {
  tokenA: string;
  tokenB: string;
  eth: string;
}

// ─── Particle Canvas ──────────────────────────────────────────────────────────
function ParticleCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d")!;
    let animId: number;
    let particles: { x: number; y: number; vx: number; vy: number; r: number; alpha: number }[] = [];

    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener("resize", resize);

    for (let i = 0; i < 80; i++) {
      particles.push({
        x: Math.random() * window.innerWidth,
        y: Math.random() * window.innerHeight,
        vx: (Math.random() - 0.5) * 0.3,
        vy: (Math.random() - 0.5) * 0.3,
        r: Math.random() * 2 + 0.5,
        alpha: Math.random() * 0.5 + 0.1,
      });
    }

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      particles.forEach((p) => {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > canvas.width) p.vx *= -1;
        if (p.y < 0 || p.y > canvas.height) p.vy *= -1;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(0,210,200,${p.alpha})`;
        ctx.fill();
      });
      animId = requestAnimationFrame(draw);
    };
    draw();
    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("resize", resize);
    };
  }, []);
  return <canvas ref={canvasRef} style={{ position: "fixed", inset: 0, zIndex: 0, pointerEvents: "none" }} />;
}

// ─── Main App ─────────────────────────────────────────────────────────────────
export default function App() {
  const { address } = useAccount();

  const [modal, setModal] = useState<Modal>(null);
  const [stats, setStats] = useState<Stats>({
    reserveA: "—",
    reserveB: "—",
  });
  const [userBalances, setUserBalances] = useState<UserBalances | null>(null);

  const fetchStats = useCallback(async () => {
    try {
      const provider = new ethers.JsonRpcProvider(SEPOLIA_RPC);

      // Reserves
      const pair = new ethers.Contract(ADDRESSES.SSPair, SSPAIR_ABI, provider);
      const [r0, r1] = await pair.getReserves();
      const token0: string = await pair.token0();
      const isAToken0 = token0.toLowerCase() === ADDRESSES.TokenA.toLowerCase();
      const reserveA = isAToken0 ? r0 : r1;
      const reserveB = isAToken0 ? r1 : r0;



      setStats({
        reserveA: parseFloat(ethers.formatUnits(reserveA, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 }),
        reserveB: parseFloat(ethers.formatUnits(reserveB, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 })
      });
    } catch {
      // silently fail — keep previous values
    }
  }, []);

  const fetchUserBalances = useCallback(async (userAddress: string) => {
    try {
      const provider = new ethers.JsonRpcProvider(SEPOLIA_RPC);

      // Fetch TokenA balance
      const tokenA = new ethers.Contract(ADDRESSES.TokenA, ERC20_ABI, provider);
      const balA = await tokenA.balanceOf(userAddress);

      // Fetch TokenB balance
      const tokenB = new ethers.Contract(ADDRESSES.TokenB, ERC20_ABI, provider);
      const balB = await tokenB.balanceOf(userAddress);

      // Fetch native ETH balance
      const ethBal = await provider.getBalance(userAddress);

      setUserBalances({
        tokenA: parseFloat(ethers.formatUnits(balA, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 }),
        tokenB: parseFloat(ethers.formatUnits(balB, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 }),
        eth: parseFloat(ethers.formatUnits(ethBal, 18)).toLocaleString(undefined, { maximumFractionDigits: 4 }),
      });
    } catch (e) {
      console.error('Failed to fetch user balances:', e);
      setUserBalances(null);
    }
  }, []);

  useEffect(() => {
    fetchStats();
    const id = setInterval(fetchStats, 15_000);
    return () => clearInterval(id);
  }, [fetchStats]);

  // Fetch user balances when wallet connects
  useEffect(() => {
    if (address) {
      fetchUserBalances(address);
      // Refresh balances every 15 seconds
      const id = setInterval(() => fetchUserBalances(address), 15_000);
      return () => clearInterval(id);
    } else {
      setUserBalances(null);
    }
  }, [address, fetchUserBalances]);

  // Listen for manual balance update events (after transactions)
  useEffect(() => {
    const handleUpdate = () => {
      if (address) fetchUserBalances(address);
    };
    window.addEventListener('balanceUpdate', handleUpdate);
    return () => window.removeEventListener('balanceUpdate', handleUpdate);
  }, [address, fetchUserBalances]);

  return (
    <div className="app-root">
      <ParticleCanvas />

      {/* ── Navbar ─────────────────────────────────────────────────────────── */}
      <nav className="navbar">
        <div className="nav-left">
          <div className="logo-mark">🛡</div>
          <span className="logo-text">ShieldSwap</span>
          <span className="chain-badge">SEPOLIA</span>
        </div>
        <div className="nav-right">
          <a
            className="github-btn"
            href="https://github.com"
            target="_blank"
            rel="noreferrer"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.3 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23A11.509 11.509 0 0 1 12 5.803c1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576C20.566 21.797 24 17.3 24 12c0-6.63-5.37-12-12-12z" />
            </svg>
            GitHub
          </a>
          <ConnectButton />
          <FaucetButton />
        </div>
      </nav>

      {/* ── Hero ──────────────────────────────────────────────────────────── */}
      <section className="hero">
        <div className="hero-badge">● POWERED BY CHAINLINK CRE &amp; GPT-4O-MINI</div>
        <h1 className="hero-title">
          Private AMM Swaps<br />
          <span className="hero-gradient">Powered by AI</span>
        </h1>
        <p className="hero-sub">
          ShieldSwap combines zero-knowledge privacy with AI-powered intelligence.
          Deposit tokens anonymously into shielded pools, leverage Chainlink price feeds
          for real-time market data, and let GPT-4o-mini optimize your swap timing -
          complete privacy with smart execution.
        </p>

        {/* Live stats bar */}
        <div className="stats-bar">
          <div className="stat-item">
            <span className="stat-value">{stats.reserveA}</span>
            <span className="stat-label">MOCK ETH RESERVE</span>
          </div>
          <div className="stat-divider" />
          <div className="stat-item">
            <span className="stat-value">{stats.reserveB}</span>
            <span className="stat-label">MOCK BTC RESERVE</span>
          </div>
          <div className="stat-divider" />

          {/* User wallet balances */}
          {userBalances && (
            <>
              <div className="stat-divider" />
              <div className="stat-item">
                <span className="stat-value user-balance">{userBalances.tokenA}</span>
                <span className="stat-label">YOUR MOCK ETH</span>
              </div>
              <div className="stat-divider" />
              <div className="stat-item">
                <span className="stat-value user-balance">{userBalances.tokenB}</span>
                <span className="stat-label">YOUR MOCK BTC</span>
              </div>
              <div className="stat-divider" />
              <div className="stat-item">
                <span className="stat-value user-balance">{userBalances.eth}</span>
                <span className="stat-label">YOUR ETH</span>
              </div>
            </>
          )}
        </div>
      </section>

      {/* ── Cards ─────────────────────────────────────────────────────────── */}
      <section className="cards-section">
        <div className="section-label">CHOOSE YOUR ACTION</div>
        <div className="cards-grid">

          {/* Deposit */}
          <div className="card card-deposit">
            <div className="card-tag card-tag-teal">PRIVACY POOL</div>
            <div className="card-icon">🔒</div>
            <h3 className="card-title">Deposit</h3>
            <p className="card-desc">
              Deposit Mock ETH or Mock BTC into shielded pools. 
Choose your denomination and receive an untraceable secret note.
            </p>
            <button className="card-btn card-btn-teal" onClick={() => setModal("deposit")}>
              Deposit Now →
            </button>
          </div>

          {/* Withdraw */}
          <div className="card card-withdraw">
            <div className="card-tag card-tag-amber">SAME TOKEN</div>
            <div className="card-icon">🔄</div>
            <h3 className="card-title">Withdraw</h3>
            <p className="card-desc">
              Privately withdraw your Mock ETH back to any address. Zero on-chain link
              between depositor and recipient.
            </p>
            <button className="card-btn card-btn-amber" onClick={() => setModal("withdraw")}>
              Withdraw Same Token →
            </button>
          </div>

          {/* Swap & Withdraw */}
          <div className="card card-swap">
            <div className="card-tag card-tag-purple">AI POWERED</div>
            <div className="card-icon">⚡</div>
            <h3 className="card-title">Swap &amp; Withdraw</h3>
            <p className="card-desc">
              AI-powered private exit. Chainlink CRE monitors pool rates every 30s and
              executes your swap to Mock BTC at the optimal time.
            </p>
            <button className="card-btn card-btn-purple" onClick={() => setModal("swapWithdraw")}>
              Swap &amp; Withdraw →
            </button>
          </div>

          {/* Normal Swap - NEW */}
          <div className="card card-normal-swap">
            <div className="card-tag card-tag-blue">ARBITRAGE</div>
            <div className="card-icon">🔄</div>
            <h3 className="card-title">Swap Tokens</h3>
            <p className="card-desc">
              Public swap between TokenA and TokenB. See live price preview before
              executing. Perfect for arbitrage opportunities.
            </p>
            <button className="card-btn card-btn-blue" onClick={() => setModal("normalSwap")}>
              Swap Now →
            </button>
          </div>

          {/* Liquidity */}
          <div className="card card-liquidity">
            <div className="card-tag card-tag-green">EARN FEES</div>
            <div className="card-icon">💧</div>
            <h3 className="card-title">Mint / Burn Liquidity</h3>
            <p className="card-desc">
              Provide liquidity to the AMM pool and earn fees from every swap while
              supporting the privacy ecosystem.
            </p>
            <button className="card-btn card-btn-green" onClick={() => setModal("liquidity")}>
              Manage Liquidity →
            </button>
          </div>

        </div>
      </section>

      {/* ── Modals ──────────────────────────────────────────────────────────── */}
      {modal === "deposit" && <DepositModal onClose={() => setModal(null)} />}
      {modal === "withdraw" && <WithdrawModal onClose={() => setModal(null)} />}
      {modal === "swapWithdraw" && <SwapWithdrawModal onClose={() => setModal(null)} />}
      {modal === "normalSwap" && <SwapModal onClose={() => setModal(null)} />}
      {modal === "liquidity" && <LiquidityModal onClose={() => setModal(null)} />}

      <style>{`
        /* ── Reset & Root ──────────────────────────────────────────────── */
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        body {
          background: #060d1a;
          color: #e2e8f0;
          font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
          min-height: 100vh;
          overflow-x: hidden;
        }

        .app-root {
          position: relative;
          min-height: 100vh;
          z-index: 1;
        }

        /* ── Navbar ────────────────────────────────────────────────────── */
        .navbar {
          position: sticky;
          top: 0;
          z-index: 100;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0 2rem;
          height: 60px;
          background: rgba(6,13,26,0.92);
          backdrop-filter: blur(12px);
          border-bottom: 1px solid rgba(0,210,200,0.12);
        }
        .nav-left { display: flex; align-items: center; gap: 0.6rem; }
        .logo-mark { font-size: 1.4rem; }
        .logo-text { font-size: 1.25rem; font-weight: 700; color: #fff; letter-spacing: -0.01em; }
        .chain-badge {
          font-size: 0.65rem;
          font-weight: 600;
          padding: 2px 8px;
          border-radius: 4px;
          border: 1px solid rgba(0,210,200,0.4);
          color: #00d2c8;
          letter-spacing: 0.08em;
        }
        .nav-right { display: flex; align-items: center; gap: 1rem; }
        .github-btn {
          display: flex;
          align-items: center;
          gap: 0.4rem;
          padding: 6px 14px;
          border-radius: 6px;
          border: 1px solid rgba(255,255,255,0.15);
          color: #cbd5e1;
          font-size: 0.85rem;
          text-decoration: none;
          transition: border-color 0.2s, color 0.2s;
        }
        .github-btn:hover { border-color: rgba(255,255,255,0.4); color: #fff; }

        /* ── Hero ──────────────────────────────────────────────────────── */
        .hero {
          position: relative;
          z-index: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          text-align: center;
          padding: 5rem 2rem 3rem;
          gap: 1.5rem;
        }
        .hero-badge {
          font-size: 0.72rem;
          letter-spacing: 0.1em;
          font-weight: 600;
          color: #00d2c8;
          padding: 6px 18px;
          border-radius: 20px;
          border: 1px solid rgba(0,210,200,0.35);
          background: rgba(0,210,200,0.07);
        }
        .hero-title {
          font-size: clamp(2.4rem, 5vw, 4rem);
          font-weight: 800;
          line-height: 1.1;
          color: #fff;
          letter-spacing: -0.02em;
        }
        .hero-gradient {
          background: linear-gradient(90deg, #00d2c8, #a855f7);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }
        .hero-sub {
          font-size: 1rem;
          color: #94a3b8;
          line-height: 1.7;
          max-width: 620px;
        }

        /* ── Stats Bar ─────────────────────────────────────────────────── */
        .stats-bar {
          display: flex;
          align-items: center;
          gap: 0;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 12px;
          padding: 1.25rem 2.5rem;
          margin-top: 0.5rem;
        }
        .stat-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.3rem;
          min-width: 130px;
        }
        .stat-value {
          font-size: 2rem;
          font-weight: 800;
          color: #00d2c8;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .stat-value.user-balance {
          color: #a855f7;
        }
        .stat-pct { font-size: 1.2rem; }
        .stat-label {
          font-size: 0.62rem;
          letter-spacing: 0.1em;
          color: #64748b;
          font-weight: 600;
        }
        .stat-divider {
          width: 1px;
          height: 40px;
          background: rgba(255,255,255,0.1);
          margin: 0 1.5rem;
        }

        /* ── Cards Section ─────────────────────────────────────────────── */
        .cards-section {
          position: relative;
          z-index: 1;
          padding: 2rem 3rem 5rem;
          max-width: 1300px;
          margin: 0 auto;
        }
        .section-label {
          text-align: center;
          font-size: 0.7rem;
          letter-spacing: 0.15em;
          color: #475569;
          font-weight: 600;
          margin-bottom: 2rem;
        }
        .cards-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1.5rem;
        }
        @media (max-width: 900px) { .cards-grid { grid-template-columns: 1fr; } }

        .card {
          position: relative;
          background: rgba(10,20,40,0.85);
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 16px;
          padding: 2rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
          overflow: hidden;
          transition: border-color 0.25s, transform 0.2s;
        }
        .card::before {
          content: '';
          position: absolute;
          inset: 0;
          border-radius: 16px;
          opacity: 0;
          transition: opacity 0.3s;
          pointer-events: none;
        }
        .card:hover { transform: translateY(-2px); }
        .card-deposit::before  { background: radial-gradient(circle at 20% 50%, rgba(0,210,200,0.06), transparent 70%); }
        .card-withdraw::before { background: radial-gradient(circle at 80% 50%, rgba(245,158,11,0.06), transparent 70%); }
        .card-swap::before     { background: radial-gradient(circle at 20% 50%, rgba(168,85,247,0.06), transparent 70%); }
        .card-normal-swap::before { background: radial-gradient(circle at 20% 80%, rgba(59,130,246,0.06), transparent 70%); }
        .card-liquidity::before{ background: radial-gradient(circle at 80% 50%, rgba(34,197,94,0.06), transparent 70%); }
        .card:hover::before    { opacity: 1; }

        .card-tag {
          display: inline-flex;
          font-size: 0.62rem;
          font-weight: 700;
          letter-spacing: 0.1em;
          padding: 3px 10px;
          border-radius: 4px;
          width: fit-content;
        }
        .card-tag-teal   { background: rgba(0,210,200,0.15);   color: #00d2c8;  border: 1px solid rgba(0,210,200,0.3); }
        .card-tag-amber  { background: rgba(245,158,11,0.12);  color: #f59e0b;  border: 1px solid rgba(245,158,11,0.3); }
        .card-tag-purple { background: rgba(168,85,247,0.12);  color: #a855f7;  border: 1px solid rgba(168,85,247,0.3); }
        .card-tag-blue   { background: rgba(59,130,246,0.12);  color: #3b82f6;  border: 1px solid rgba(59,130,246,0.3); }
        .card-tag-green  { background: rgba(34,197,94,0.12);   color: #22c55e;  border: 1px solid rgba(34,197,94,0.3); }

        .card-icon { font-size: 2.5rem; }
        .card-title { font-size: 1.6rem; font-weight: 700; color: #fff; }
        .card-desc { font-size: 0.9rem; color: #64748b; line-height: 1.6; flex: 1; }

        .card-btn {
          padding: 0.85rem 1.5rem;
          border-radius: 8px;
          font-size: 0.9rem;
          font-weight: 600;
          cursor: pointer;
          transition: background 0.2s, opacity 0.2s;
          background: transparent;
          border: 1.5px solid;
          letter-spacing: 0.02em;
        }
        .card-btn:hover { opacity: 0.8; }
        .card-btn-teal   { border-color: #00d2c8;  color: #00d2c8; }
        .card-btn-amber  { border-color: #f59e0b;  color: #f59e0b; }
        .card-btn-purple { border-color: #a855f7;  color: #a855f7; }
        .card-btn-blue   { border-color: #3b82f6;  color: #3b82f6; }
        .card-btn-green  { border-color: #22c55e;  color: #22c55e; }
        .card-btn-teal:hover   { background: rgba(0,210,200,0.1); }
        .card-btn-amber:hover  { background: rgba(245,158,11,0.1); }
        .card-btn-purple:hover { background: rgba(168,85,247,0.1); }
        .card-btn-blue:hover   { background: rgba(59,130,246,0.1); }
        .card-btn-green:hover  { background: rgba(34,197,94,0.1); }

        /* ── Modal Overlay ─────────────────────────────────────────────── */
        .modal-overlay {
          position: fixed;
          inset: 0;
          z-index: 200;
          background: rgba(0,0,0,0.75);
          backdrop-filter: blur(6px);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 1rem;
        }
        .modal-box {
          position: relative;
          background: #0c1829;
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 16px;
          padding: 2rem;
          width: 100%;
          max-width: 520px;
          max-height: 90vh;
          overflow-y: auto;
        }
        .modal-box-wide { max-width: 640px; }
        .modal-close {
          position: absolute;
          top: 1rem;
          right: 1rem;
          background: rgba(255,255,255,0.07);
          border: none;
          color: #94a3b8;
          width: 28px;
          height: 28px;
          border-radius: 50%;
          cursor: pointer;
          font-size: 0.8rem;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: background 0.2s;
        }
        .modal-close:hover { background: rgba(255,255,255,0.15); color: #fff; }

        .modal-header {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
          margin-bottom: 1.5rem;
        }
        .modal-icon { font-size: 2rem; }
        .modal-header h2 { font-size: 1.6rem; font-weight: 700; color: #fff; }
        .modal-sub { font-size: 0.85rem; color: #64748b; }

        .modal-amount-badge {
          background: rgba(0,210,200,0.08);
          border: 1px solid rgba(0,210,200,0.25);
          border-radius: 8px;
          padding: 0.7rem 1rem;
          font-size: 0.9rem;
          color: #cbd5e1;
          margin-bottom: 1rem;
        }
        .modal-amount-badge strong { color: #00d2c8; }

        .modal-section { display: flex; flex-direction: column; gap: 1rem; }
        .modal-section.center { align-items: center; text-align: center; padding: 2rem 0; }
        .modal-hint { font-size: 0.85rem; color: #94a3b8; line-height: 1.6; }

        .input-label { font-size: 0.82rem; color: #94a3b8; font-weight: 500; }
        .modal-input {
          width: 100%;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 8px;
          padding: 0.75rem 1rem;
          color: #e2e8f0;
          font-size: 0.9rem;
          outline: none;
          transition: border-color 0.2s;
        }
        .modal-input:focus { border-color: #00d2c8; }
        .modal-textarea {
          width: 100%;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 8px;
          padding: 0.75rem 1rem;
          color: #e2e8f0;
          font-size: 0.82rem;
          font-family: 'Courier New', monospace;
          outline: none;
          resize: vertical;
          transition: border-color 0.2s;
        }
        .modal-textarea:focus { border-color: #00d2c8; }

        .modal-hint-box {
          background: rgba(255,255,255,0.03);
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 8px;
          padding: 0.75rem 1rem;
          font-size: 0.82rem;
          color: #64748b;
          line-height: 1.5;
        }

        /* Buttons */
        .btn-primary {
          width: 100%;
          padding: 0.85rem;
          border-radius: 8px;
          background: rgba(0,210,200,0.15);
          border: 1.5px solid #00d2c8;
          color: #00d2c8;
          font-size: 0.9rem;
          font-weight: 600;
          cursor: pointer;
          transition: background 0.2s;
        }
        .btn-primary:hover:not(:disabled) { background: rgba(0,210,200,0.25); }
        .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
        .btn-green  { border-color: #22c55e; color: #22c55e; background: rgba(34,197,94,0.12); }
        .btn-green:hover:not(:disabled) { background: rgba(34,197,94,0.22); }
        .btn-amber  { border-color: #f59e0b; color: #f59e0b; background: rgba(245,158,11,0.12); }
        .btn-amber:hover:not(:disabled) { background: rgba(245,158,11,0.22); }
        .btn-purple { border-color: #a855f7; color: #a855f7; background: rgba(168,85,247,0.12); }
        .btn-purple:hover:not(:disabled) { background: rgba(168,85,247,0.22); }
        .btn-teal   { border-color: #00d2c8; color: #00d2c8; background: rgba(0,210,200,0.12); }
        .btn-teal:hover:not(:disabled) { background: rgba(0,210,200,0.22); }
        .btn-danger {
          width: 100%;
          padding: 0.75rem;
          border-radius: 8px;
          background: rgba(239,68,68,0.12);
          border: 1.5px solid #ef4444;
          color: #ef4444;
          font-size: 0.88rem;
          font-weight: 600;
          cursor: pointer;
          margin-top: 0.5rem;
          transition: background 0.2s;
        }
        .btn-danger:hover { background: rgba(239,68,68,0.22); }

        /* Note box */
        .note-box {
          background: rgba(0,0,0,0.4);
          border: 1px solid rgba(0,210,200,0.3);
          border-radius: 8px;
          padding: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .note-label { font-size: 0.75rem; color: #00d2c8; font-weight: 600; letter-spacing: 0.05em; }
        .note-value {
          font-family: 'Courier New', monospace;
          font-size: 0.75rem;
          color: #e2e8f0;
          word-break: break-all;
          line-height: 1.5;
        }
        .btn-copy {
          align-self: flex-end;
          padding: 4px 12px;
          border-radius: 4px;
          border: 1px solid rgba(0,210,200,0.3);
          background: transparent;
          color: #00d2c8;
          font-size: 0.78rem;
          cursor: pointer;
          transition: background 0.2s;
        }
        .btn-copy:hover { background: rgba(0,210,200,0.1); }

        /* Warning boxes */
        .warning-box {
          background: rgba(245,158,11,0.08);
          border: 1px solid rgba(245,158,11,0.3);
          border-radius: 8px;
          padding: 0.85rem 1rem;
          font-size: 0.82rem;
          color: #fbbf24;
          line-height: 1.6;
        }
        .warning-red {
          background: rgba(239,68,68,0.08);
          border-color: rgba(239,68,68,0.3);
          color: #f87171;
        }

        .commitment-preview {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.78rem;
        }
        .label-small { color: #64748b; font-size: 0.78rem; }
        .mono-small { font-family: 'Courier New', monospace; color: #94a3b8; font-size: 0.75rem; }

        /* Parsed info */
        .parsed-info {
          background: rgba(0,210,200,0.05);
          border: 1px solid rgba(0,210,200,0.15);
          border-radius: 8px;
          padding: 0.75rem 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.4rem;
        }
        .parsed-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 1rem;
        }

        /* Status */
        .status-text { font-size: 1rem; color: #e2e8f0; font-weight: 600; }
        .status-sub { font-size: 0.85rem; color: #64748b; }

        /* Banners */
        .success-banner {
          padding: 0.75rem 1.5rem;
          border-radius: 8px;
          background: rgba(34,197,94,0.15);
          border: 1px solid #22c55e;
          color: #22c55e;
          font-size: 1rem;
          font-weight: 600;
          margin-bottom: 0.5rem;
        }
        .error-banner {
          padding: 0.75rem 1.5rem;
          border-radius: 8px;
          background: rgba(239,68,68,0.12);
          border: 1px solid #ef4444;
          color: #ef4444;
          font-size: 1rem;
          font-weight: 600;
          margin-bottom: 0.5rem;
        }
        .error-msg { font-size: 0.82rem; color: #94a3b8; max-width: 400px; word-break: break-word; }
        .error-inline {
          font-size: 0.8rem;
          color: #f87171;
          padding: 0.4rem 0.75rem;
          background: rgba(239,68,68,0.08);
          border-radius: 4px;
        }

        .tx-link {
          font-size: 0.85rem;
          color: #00d2c8;
          text-decoration: none;
          margin-bottom: 0.5rem;
        }
        .tx-link:hover { text-decoration: underline; }

        /* Spinner */
        @keyframes spin { to { transform: rotate(360deg); } }
        .spinner {
          width: 40px; height: 40px;
          border: 3px solid rgba(0,210,200,0.2);
          border-top-color: #00d2c8;
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
          margin-bottom: 0.5rem;
        }

        /* Tabs */
        .tab-row {
          display: flex;
          gap: 0.5rem;
          margin-bottom: 0.5rem;
        }
        .tab-btn {
          flex: 1;
          padding: 0.65rem;
          border-radius: 8px;
          border: 1.5px solid rgba(255,255,255,0.1);
          background: transparent;
          color: #64748b;
          font-size: 0.85rem;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s;
        }
        .tab-active {
          border-color: #00d2c8;
          color: #00d2c8;
          background: rgba(0,210,200,0.08);
        }

        /* ── CRE Terminal ──────────────────────────────────────────────── */
        .terminal-header {
          display: flex;
          align-items: center;
          gap: 0.4rem;
          background: rgba(0,0,0,0.5);
          padding: 0.5rem 0.75rem;
          border-radius: 8px 8px 0 0;
          border: 1px solid rgba(0,210,200,0.15);
          border-bottom: none;
        }
        .terminal-dot {
          width: 10px; height: 10px;
          border-radius: 50%;
        }
        .terminal-dot.red    { background: #ef4444; }
        .terminal-dot.yellow { background: #f59e0b; }
        .terminal-dot.green  { background: #22c55e; }
        .terminal-title {
          flex: 1;
          text-align: center;
          font-size: 0.72rem;
          letter-spacing: 0.1em;
          color: #475569;
          font-weight: 600;
        }
        .terminal-confidence {
          font-size: 0.75rem;
          color: #a855f7;
          font-weight: 600;
          font-family: 'Courier New', monospace;
        }
        .terminal-body {
          background: rgba(0,0,0,0.7);
          border: 1px solid rgba(0,210,200,0.15);
          border-radius: 0 0 8px 8px;
          padding: 1rem;
          min-height: 280px;
          max-height: 360px;
          overflow-y: auto;
          font-family: 'Courier New', monospace;
          font-size: 0.78rem;
          line-height: 1.7;
        }
        .terminal-line { display: block; }
        .terminal-time { color: #334155; }
        @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0; } }
        .terminal-cursor {
          color: #00d2c8;
          animation: blink 1s step-end infinite;
          display: inline-block;
        }
        .lp-balance-hint {
          font-size: 0.8rem;
          color: #64748b;
          padding: 6px 10px;
          background: rgba(0,210,200,0.05);
          border: 1px solid rgba(0,210,200,0.12);
          border-radius: 6px;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.4rem;
          transition: background 0.2s;
        }
        .lp-balance-hint:hover { background: rgba(0,210,200,0.1); }
        .lp-balance-hint strong { color: #00d2c8; }
        .lp-max-btn {
          font-size: 0.7rem;
          font-weight: 700;
          color: #00d2c8;
          padding: 2px 7px;
          border: 1px solid rgba(0,210,200,0.3);
          border-radius: 4px;
        }
      `}</style>
    </div>
  );
}