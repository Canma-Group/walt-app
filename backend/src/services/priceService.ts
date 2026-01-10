import axios from "axios";

interface PriceCache {
  prices: Record<string, number>;
  pricesIDR: Record<string, number>;
  lastUpdated: number;
  indodaxLastUpdated: number;
}

const INDODAX_API = "https://indodax.com/api";
const COINCAP_API = "https://api.coincap.io/v2";
const CACHE_TTL = 1000; // 1 second - real-time price updates

// Indodax pair mapping (symbol -> ticker_id)
const INDODAX_PAIRS: Record<string, string> = {
  LSK: 'lsk_idr',
  ETH: 'eth_idr',
  BTC: 'btc_idr',
  USDT: 'usdt_idr',
  USDC: 'usdc_idr',
  POL: 'pol_idr',
  MATIC: 'matic_idr',
  SOL: 'sol_idr',
  BNB: 'bnb_idr',
  XRP: 'xrp_idr',
  DOGE: 'doge_idr',
  ADA: 'ada_idr',
  DOT: 'dot_idr',
  LINK: 'link_idr',
  UNI: 'uni_idr',
  AVAX: 'avax_idr',
  SHIB: 'shib_idr',
};

// Token ID mapping for CoinCap (fallback)
const TOKEN_IDS: Record<string, string> = {
  POL: "matic-network",
  MATIC: "matic-network", 
  ETH: "ethereum",
  BTC: "bitcoin",
  USDT: "tether",
  USDC: "usd-coin",
  LSK: "lisk",
};

let priceCache: PriceCache = {
  prices: {},
  pricesIDR: {},
  lastUpdated: 0,
  indodaxLastUpdated: 0,
};

// USD to IDR rate
let usdToIdr = 16700;

export async function updateUsdToIdr(): Promise<void> {
  try {
    // Use a free forex API or hardcode approximate rate
    const response = await axios.get(
      "https://api.exchangerate-api.com/v4/latest/USD",
      { timeout: 5000 }
    );
    if (response.data?.rates?.IDR) {
      usdToIdr = response.data.rates.IDR;
    }
  } catch (e) {
    // Disabled verbose logging
    // console.log("[PriceService] Using default USD/IDR rate:", usdToIdr);
  }
}

// Fallback prices in IDR (updated for current market)
const FALLBACK_PRICES_IDR: Record<string, number> = {
  LSK: 3400,
  ETH: 58500000,
  BTC: 1500000000,
  POL: 7500,
  MATIC: 7500,
  USDT: 16700,
  USDC: 16700,
  SOL: 2150000,
  BNB: 14700000,
  XRP: 32000,
  DOGE: 2250,
  ADA: 6200,
  DOT: 33500,
  LINK: 218000,
  UNI: 99350,
  AVAX: 223000,
  SHIB: 0.37,
};

// Fallback prices in USD
const FALLBACK_PRICES: Record<string, number> = {
  LSK: 0.20,
  ETH: 3500,
  BTC: 95000,
  POL: 0.45,
  MATIC: 0.45,
  USDT: 1.0,
  USDC: 1.0,
};

/**
 * Fetch prices from Indodax API (IDR native - most accurate for Indonesia)
 * Updates every 5 seconds for real-time conversion
 */
export async function fetchPricesFromIndodax(): Promise<Record<string, number>> {
  const now = Date.now();
  
  // Return cached if still valid
  if (now - priceCache.indodaxLastUpdated < CACHE_TTL && Object.keys(priceCache.pricesIDR).length > 0) {
    return priceCache.pricesIDR;
  }

  const pricesIDR: Record<string, number> = {};
  
  try {
    // Disabled verbose logging for troubleshooting
    // console.log("[PriceService] Fetching prices from Indodax API...");
    const response = await axios.get(`${INDODAX_API}/summaries`, {
      timeout: 10000,
    });

    if (response.data?.tickers) {
      const tickers = response.data.tickers;
      
      for (const [symbol, pair] of Object.entries(INDODAX_PAIRS)) {
        const ticker = tickers[pair];
        if (ticker?.last) {
          const price = parseFloat(ticker.last);
          if (price > 0) {
            pricesIDR[symbol] = price;
            // Disabled verbose per-coin logging
            // console.log(`[PriceService] ${symbol}: Rp ${price.toLocaleString()} (Indodax)`);
          }
        }
      }
    }

    // Update cache
    priceCache.pricesIDR = { ...priceCache.pricesIDR, ...pricesIDR };
    priceCache.indodaxLastUpdated = now;
    
    // Disabled verbose logging
    // console.log(`[PriceService] Updated ${Object.keys(pricesIDR).length} prices from Indodax`);
  } catch (e: any) {
    console.warn("[PriceService] Indodax API failed:", e.message);
    // Return cached or fallback
    if (Object.keys(priceCache.pricesIDR).length > 0) {
      return priceCache.pricesIDR;
    }
  }

  // Use fallback for missing symbols
  for (const [symbol, fallbackPrice] of Object.entries(FALLBACK_PRICES_IDR)) {
    if (!pricesIDR[symbol]) {
      pricesIDR[symbol] = fallbackPrice;
    }
  }

  return pricesIDR;
}

export async function fetchPrices(symbols: string[]): Promise<Record<string, number>> {
  const now = Date.now();
  
  // Return cached if still valid
  if (now - priceCache.lastUpdated < CACHE_TTL) {
    const cached: Record<string, number> = {};
    for (const symbol of symbols) {
      if (priceCache.prices[symbol.toUpperCase()]) {
        cached[symbol.toUpperCase()] = priceCache.prices[symbol.toUpperCase()];
      }
    }
    if (Object.keys(cached).length === symbols.length) {
      return cached;
    }
  }

  const prices: Record<string, number> = {};
  
  // Try to fetch from CoinCap API
  try {
    const response = await axios.get(`${COINCAP_API}/assets`, {
      params: { limit: 100 },
      timeout: 10000,
    });

    if (response.data?.data) {
      for (const asset of response.data.data) {
        for (const [symbol, coinCapId] of Object.entries(TOKEN_IDS)) {
          if (asset.id === coinCapId && asset.priceUsd) {
            prices[symbol] = parseFloat(asset.priceUsd);
          }
        }
      }
    }
  } catch (e: any) {
    console.warn("[PriceService] CoinCap API failed:", e.message);
  }

  // Use fallback for missing symbols
  for (const symbol of symbols) {
    const upper = symbol.toUpperCase();
    if (!prices[upper] && FALLBACK_PRICES[upper]) {
      prices[upper] = FALLBACK_PRICES[upper];
    }
  }

  // Update cache
  priceCache.prices = { ...priceCache.prices, ...prices };
  priceCache.lastUpdated = now;

  return prices;
}

export async function fetchPricesIDR(symbols: string[]): Promise<Record<string, number>> {
  const usdPrices = await fetchPrices(symbols);
  const idrPrices: Record<string, number> = {};

  for (const [symbol, usdPrice] of Object.entries(usdPrices)) {
    idrPrices[symbol] = usdPrice * usdToIdr;
  }

  priceCache.pricesIDR = idrPrices;
  return idrPrices;
}

export function getUsdToIdr(): number {
  return usdToIdr;
}

export async function getTokenPriceUSD(symbol: string): Promise<number> {
  const prices = await fetchPrices([symbol]);
  return prices[symbol.toUpperCase()] || 0;
}

export async function getTokenPriceIDR(symbol: string): Promise<number> {
  const prices = await fetchPricesIDR([symbol]);
  return prices[symbol.toUpperCase()] || 0;
}

export interface TokenWithPrice {
  symbol: string;
  balance: number;
  priceUSD: number;
  priceIDR: number;
  valueUSD: number;
  valueIDR: number;
}

export async function calculateTotalBalanceIDR(
  balances: Array<{ symbol: string; balance: number }>
): Promise<{
  tokens: TokenWithPrice[];
  totalUSD: number;
  totalIDR: number;
}> {
  const symbols = balances.map((b) => b.symbol);
  const pricesUSD = await fetchPrices(symbols);
  
  let totalUSD = 0;
  const tokens: TokenWithPrice[] = [];

  for (const { symbol, balance } of balances) {
    const priceUSD = pricesUSD[symbol.toUpperCase()] || 0;
    const priceIDR = priceUSD * usdToIdr;
    const valueUSD = balance * priceUSD;
    const valueIDR = balance * priceIDR;
    
    totalUSD += valueUSD;
    
    tokens.push({
      symbol,
      balance,
      priceUSD,
      priceIDR,
      valueUSD,
      valueIDR,
    });
  }

  return {
    tokens,
    totalUSD,
    totalIDR: totalUSD * usdToIdr,
  };
}

// Initialize USD/IDR rate on startup
updateUsdToIdr();
