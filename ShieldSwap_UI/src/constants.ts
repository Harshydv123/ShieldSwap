export const ADDRESSES = {
  // Multi-denomination ShieldPools
  ShieldPools: {
    TokenA_100: "0xa9d547007B9ce930dde76Ce038ce2f0aa53F1F5E",
    TokenA_10:  "0x28Faf0AFe004Cbb580d6257E5f84a413881cD826",
    TokenA_1:   "0x6660199DF1A7e83AA99A2b3d6a485f4c39151378",
    TokenB_10:  "0xA992DD5c48E294b400A1ee6EF67376F2FF784121",
    TokenB_1:   "0x529d60bd71c0518cdCeCd43644DF7595d111C6e0",
  },
  ShieldPool: "0xa9d547007B9ce930dde76Ce038ce2f0aa53F1F5E",
  // AMM
  SSPair:     "0x99E95668B7f2662b7FADf8C7B6e90F4240b2E6a8",
  SSRouter:   "0xfeb4141299997bE4EDE9b012A5bbAe171eE44c6f",
  // Tokens
  TokenA:     "0x68df70070872b49670190c9c6f77478Fc9Bc2f48",
  TokenB:     "0x4474bD760d67a8a67e78Cea49886deFd4C8Ce34e",
  // Chainlink Sepolia feeds
  ETH_USD:    "0x694AA1769357215DE4FAC081bf1f309aDC325306",
  BTC_USD:    "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
} as const;

// ─── API Keys ─────────────────────────────────────────────────────────────────
export const OPENAI_API_KEY = "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";

// ─── Field Size for ZK commitments ────────────────────────────────────────────
export const FIELD_SIZE = BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617");

// ─── Denominations ────────────────────────────────────────────────────────────
export const DENOMINATIONS = {
  TokenA_100: BigInt("100000000000000000000"), // 100 * 1e18
  TokenA_10:  BigInt("10000000000000000000"),  // 10 * 1e18
  TokenA_1:   BigInt("1000000000000000000"),   // 1 * 1e18
  TokenB_10:  BigInt("10000000000000000000"),  // 10 * 1e18
  TokenB_1:   BigInt("1000000000000000000"),   // 1 * 1e18
} as const;

export const DENOMINATION = BigInt("100000000000000000000"); // 100e18

// ─── ABIs ─────────────────────────────────────────────────────────────────────
export const SHIELD_POOL_ABI = [
  "function deposit(bytes32 _commitment) external",
  "function withdraw(bytes _proof, bytes32 _root, bytes32 _nullifierHash, address _recipient, address _relayer, uint256 _fee) external",
  "function swapAndWithdraw(bytes _proof, bytes32 _root, bytes32 _nullifierHash, address _recipient, address _tokenOut, uint256 _amountOutMin, address _relayer, uint256 _fee) external",
  "function getLastRoot() external view returns (bytes32)",
  "function totalDeposits() external view returns (uint256)",
  "function nullifierHashes(bytes32) external view returns (bool)",
];

export const SSPAIR_ABI = [
  "function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)",
  "function token0() external view returns (address)",
  "function token1() external view returns (address)",
  "function balanceOf(address) external view returns (uint256)",
  "function approve(address spender, uint256 value) external returns (bool)",
  "function totalSupply() external view returns (uint256)",
];

export const SSROUTER_ABI = [
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)",
  "function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, address to) external returns (uint256 amountA, uint256 amountB)",
  "function swapExactTokensForTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, address to) external returns (uint256 amountOut)",
  "function getPair(address tokenA, address tokenB) external view returns (address pair)",
  "function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut)",
];

export const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
];

export const CHAINLINK_ABI = [
  "function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
];