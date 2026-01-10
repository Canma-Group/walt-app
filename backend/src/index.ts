// Firebase Admin & Functions
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import cors from "cors";
import express from "express";
import * as path from "path";
import * as fs from "fs";
import * as crypto from "crypto";
import { ethers } from "ethers";

// Initialize Firebase Admin
admin.initializeApp();

// Initialize Firestore (use directly, not from config to avoid circular dependency)
const db = admin.firestore();

// CORS configuration
const corsHandler = cors({origin: true});

// Express app for REST API
const app = express();
app.use(corsHandler);
app.use(express.json());

// Import services
import {xenditWebhook} from "./webhooks/xendit";
import {createQRISPayment, CreateQRISParams} from "./services/onrampService";
import {getLSKBalance} from "./config/lisk";
import {getPOLBalance} from "./config/polygon";
import {getAllLedgerBalances, manualRecordDeposit} from "./services/ledgerService";
import {runDepositListener} from "./services/depositListener";
import {fetchPrices, fetchPricesIDR, calculateTotalBalanceIDR, getUsdToIdr} from "./services/priceService";
import {QrisPaymentService} from "./services/qrisPaymentService";
import {DepositVerifier} from "./services/depositVerifier";

// Initialize QRIS Payment Service
const escrowMasterMnemonic = process.env.ESCROW_MASTER_MNEMONIC || "your-escrow-master-mnemonic-here";
let qrisPaymentService: QrisPaymentService | null = null;
let depositVerifier: DepositVerifier | null = null;

try {
  qrisPaymentService = new QrisPaymentService(escrowMasterMnemonic);
  depositVerifier = new DepositVerifier(qrisPaymentService);
  depositVerifier.start(10); // Check every 10 seconds
  console.log("[QRIS] Payment service initialized");
} catch (error) {
  console.error("[QRIS] Failed to initialize payment service:", error);
}

/**
 * SINGLE ENDPOINT: /login
 * Handles Web3Auth + Firebase authentication
 * 
 * Flow:
 * 1. Client sends Firebase ID Token (from Web3Auth)
 * 2. Backend verifies token
 * 3. Backend creates/updates user in Firestore
 * 4. Returns user data + wallet address
 */
app.post("/login", async (req, res) => {
  try {
    const {idToken} = req.body;

    if (!idToken) {
      return res.status(400).json({
        success: false,
        error: "idToken is required",
      });
    }

    // Verify Firebase ID Token
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const email = decodedToken.email;
    const displayName = decodedToken.name || email?.split("@")[0] || "User";

    // Get or create user in Firestore
    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();

    let userData: any = {
      email,
      name: displayName,
      photoURL: decodedToken.picture,
      lastLogin: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    if (!userDoc.exists) {
      // New user - create document
      userData.createdAt = new Date().toISOString();
      await userRef.set(userData);
    } else {
      // Existing user - update last login
      await userRef.update(userData);
      userData = {...userDoc.data(), ...userData};
    }

    // Return user data (wallet address will be added when user first top-up)
    return res.status(200).json({
      success: true,
      data: {
        userId: uid,
        ...userData,
        token: idToken, // Return token for client to use
      },
    });
  } catch (error) {
    console.error("Login error:", error);
    return res.status(401).json({
      success: false,
      error: error instanceof Error ? error.message : "Authentication failed",
    });
  }
});

/**
 * Register user endpoint
 * POST /register - Create Firestore user document with hashed PIN
 * 
 * Body:
 * - name: string
 * - phoneNumber: string
 * - email: string
 * - pin: string (6 digits, will be hashed)
 * 
 * Note: Firebase Auth user should already be created by client
 * This endpoint just creates/updates Firestore document
 */
app.post("/register", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    const decodedToken = await admin.auth().verifyIdToken(token);
    const uid = decodedToken.uid;

    const {name, phoneNumber, email, pin} = req.body;

    if (!name || !phoneNumber || !email) {
      return res.status(400).json({
        success: false,
        error: "Name, phoneNumber, and email are required",
      });
    }

    // Validate PIN format (6 digits)
    if (pin && (!/^\d{6}$/.test(pin))) {
      return res.status(400).json({
        success: false,
        error: "PIN must be 6 digits",
      });
    }

    // Hash PIN with salt if provided
    let pinHash: string | undefined;
    let pinSalt: string | undefined;
    
    if (pin) {
      // Generate random salt
      pinSalt = crypto.randomBytes(16).toString("base64");
      
      // Hash PIN with salt (SHA-256)
      const pinBytes = Buffer.from(pin, "utf8");
      const saltBytes = Buffer.from(pinSalt, "base64");
      const combined = Buffer.concat([pinBytes, saltBytes]);
      pinHash = crypto.createHash("sha256").update(combined).digest("hex");
    }

    // Create/update user document in Firestore
    const userData: any = {
      name,
      phone_number: phoneNumber,
      email,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (pinHash && pinSalt) {
      userData.pin_hash = pinHash;
      userData.pin_salt = pinSalt;
    }

    await db.collection("users").doc(uid).set(userData, {merge: true});

    return res.status(200).json({
      success: true,
      data: {
        userId: uid,
        name,
        phoneNumber,
        email,
        pinSet: !!pin,
      },
    });
  } catch (error) {
    console.error("Register error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Registration failed",
    });
  }
});

/**
 * Verify PIN endpoint
 * POST /verify-pin - Verify PIN for transactions
 * 
 * Body:
 * - pin: string (6 digits)
 * 
 * Returns: {success: boolean, verified: boolean}
 */
app.post("/verify-pin", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    const decodedToken = await admin.auth().verifyIdToken(token);
    const uid = decodedToken.uid;

    const {pin} = req.body;

    if (!pin || !/^\d{6}$/.test(pin)) {
      return res.status(400).json({
        success: false,
        error: "PIN must be 6 digits",
      });
    }

    // Get user document from Firestore
    const userDoc = await db.collection("users").doc(uid).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User not found",
      });
    }

    const userData = userDoc.data();
    const storedPinHash = userData?.pin_hash;
    const storedPinSalt = userData?.pin_salt;

    if (!storedPinHash || !storedPinSalt) {
      return res.status(400).json({
        success: false,
        error: "PIN not set for this user",
      });
    }

    // Hash provided PIN with stored salt
    const pinBytes = Buffer.from(pin, "utf8");
    const saltBytes = Buffer.from(storedPinSalt, "base64");
    const combined = Buffer.concat([pinBytes, saltBytes]);
    const computedHash = crypto.createHash("sha256").update(combined).digest("hex");

    // Compare hashes
    const verified = computedHash === storedPinHash;

    return res.status(200).json({
      success: true,
      verified,
    });
  } catch (error) {
    console.error("Verify PIN error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "PIN verification failed",
    });
  }
});

/**
 * Helper endpoint: Create QRIS (requires authentication via header)
 */
app.post("/create-qris", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    const decodedToken = await admin.auth().verifyIdToken(token);
    const uid = decodedToken.uid;

    const {amountInIDR, userWalletAddress} = req.body as CreateQRISParams;

    if (!amountInIDR || amountInIDR < 10000) {
      return res.status(400).json({
        success: false,
        error: "Minimum top-up amount is Rp 10,000",
      });
    }

    if (!userWalletAddress || !userWalletAddress.startsWith("0x")) {
      return res.status(400).json({
        success: false,
        error: "Invalid wallet address",
      });
    }

    // Auto-save wallet address to Firestore
    await db.collection("users").doc(uid).set({
      walletAddress: userWalletAddress,
      lastActivity: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }, {merge: true});

    const qrisResponse = await createQRISPayment({
      amountInIDR,
      userId: uid,
      userWalletAddress,
    });

    return res.status(200).json({
      success: true,
      data: qrisResponse,
    });
  } catch (error) {
    console.error("Create QRIS error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Helper endpoint: Get balance (requires authentication)
 */
app.get("/balance/:walletAddress", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    await admin.auth().verifyIdToken(token);

    const {walletAddress} = req.params;

    if (!walletAddress || !walletAddress.startsWith("0x")) {
      return res.status(400).json({
        success: false,
        error: "Invalid wallet address",
      });
    }

    const balance = await getLSKBalance(walletAddress);

    return res.status(200).json({
      success: true,
      data: {
        balance,
        currency: "LSK",
        walletAddress,
      },
    });
  } catch (error) {
    console.error("Get balance error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Webhook endpoint for Xendit
 */
app.post("/xendit-webhook", xenditWebhook);

// ============ MULTI-CHAIN LEDGER ENDPOINTS ============

/**
 * Get all token balances for a user (on-chain + ledger)
 * GET /tokens/:walletAddress
 */
app.get("/tokens/:walletAddress", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    await admin.auth().verifyIdToken(token);

    const {walletAddress} = req.params;

    if (!walletAddress || !walletAddress.startsWith("0x")) {
      return res.status(400).json({
        success: false,
        error: "Invalid wallet address",
      });
    }

    // Get on-chain balances from multiple chains
    const tokens = [];

    // 1. Lisk Sepolia LSK balance (native)
    try {
      const lskBalance = await getLSKBalance(walletAddress);
      if (parseFloat(lskBalance) > 0) {
        tokens.push({
          chainId: 4202,
          chainName: "Lisk Sepolia",
          symbol: "ETH",
          name: "Lisk Sepolia ETH",
          balance: lskBalance,
          tokenAddress: "0x0000000000000000000000000000000000000000",
          type: "native",
          icon: "https://raw.githubusercontent.com/LiskHQ/lisk-sdk/main/docs/assets/lisk-logo.png",
        });
      }
    } catch (e) {
      console.error("Error fetching LSK balance:", e);
    }

    // 2. Polygon POL balance (on-chain)
    try {
      const polBalance = await getPOLBalance(walletAddress);
      if (parseFloat(polBalance) > 0) {
        tokens.push({
          chainId: 137,
          chainName: "Polygon",
          symbol: "POL",
          name: "Polygon",
          balance: polBalance,
          tokenAddress: "0x0000000000000000000000000000000000000000",
          type: "native",
          icon: "https://raw.githubusercontent.com/maticnetwork/polygon-token-assets/main/assets/tokenAssets/matic.svg",
        });
      }
    } catch (e) {
      console.error("Error fetching POL balance:", e);
    }

    // 3. Ledger balances (recorded cross-chain deposits)
    try {
      const ledgerBalances = await getAllLedgerBalances(walletAddress);
      for (const lb of ledgerBalances) {
        tokens.push({
          chainId: lb.chainId,
          chainName: lb.chainName + " (Ledger)",
          symbol: lb.symbol,
          name: lb.symbol + " (Recorded)",
          balance: lb.balance,
          tokenAddress: lb.token,
          type: "ledger",
          icon: null,
        });
      }
    } catch (e) {
      console.error("Error fetching ledger balances:", e);
    }

    return res.status(200).json({
      success: true,
      data: {
        walletAddress,
        tokens,
        totalTokens: tokens.length,
      },
    });
  } catch (error) {
    console.error("Get tokens error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Record a deposit manually (for verified transactions)
 * POST /record-deposit
 */
app.post("/record-deposit", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    const decodedToken = await admin.auth().verifyIdToken(token);
    const uid = decodedToken.uid;

    const {walletAddress, chainId, tokenAddress, amount, txHash} = req.body;

    if (!walletAddress || !walletAddress.startsWith("0x")) {
      return res.status(400).json({
        success: false,
        error: "Invalid wallet address",
      });
    }

    if (!chainId || !txHash) {
      return res.status(400).json({
        success: false,
        error: "chainId and txHash are required",
      });
    }

    // Verify user owns this wallet
    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data();
    
    if (userData?.wallet_address?.toLowerCase() !== walletAddress.toLowerCase()) {
      return res.status(403).json({
        success: false,
        error: "Wallet address does not belong to authenticated user",
      });
    }

    // Record the deposit
    const liskTxHash = await manualRecordDeposit(
      walletAddress,
      chainId,
      tokenAddress || "0x0000000000000000000000000000000000000000",
      amount,
      txHash
    );

    // Save to Firestore
    await db.collection("deposits").add({
      userId: uid,
      walletAddress,
      sourceChainId: chainId,
      tokenAddress: tokenAddress || "0x0000000000000000000000000000000000000000",
      amount,
      sourceTxHash: txHash,
      liskTxHash,
      recordedAt: new Date().toISOString(),
      status: "recorded",
    });

    return res.status(200).json({
      success: true,
      data: {
        liskTxHash,
        message: "Deposit recorded successfully on Lisk ledger",
      },
    });
  } catch (error) {
    console.error("Record deposit error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Get deposit history for a user
 * GET /deposits/:walletAddress
 */
app.get("/deposits/:walletAddress", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    await admin.auth().verifyIdToken(token);

    const {walletAddress} = req.params;

    const depositsSnapshot = await db.collection("deposits")
      .where("walletAddress", "==", walletAddress.toLowerCase())
      .orderBy("recordedAt", "desc")
      .limit(50)
      .get();

    const deposits: any[] = [];
    depositsSnapshot.forEach((doc) => {
      deposits.push({id: doc.id, ...doc.data()});
    });

    return res.status(200).json({
      success: true,
      data: deposits,
    });
  } catch (error) {
    console.error("Get deposits error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Run deposit listener manually (for testing)
 * POST /run-listener
 */
app.post("/run-listener", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        error: "Authorization token required",
      });
    }

    const token = authHeader.split("Bearer ")[1];
    await admin.auth().verifyIdToken(token);

    const result = await runDepositListener();

    return res.status(200).json({
      success: true,
      data: result,
    });
  } catch (error) {
    console.error("Run listener error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * Swagger Documentation Endpoint
 * GET /swagger.json - Returns OpenAPI 3.0 specification
 */
app.get("/swagger.json", (req, res) => {
  try {
    const swaggerPath = path.join(__dirname, "../swagger.json");
    const swaggerContent = fs.readFileSync(swaggerPath, "utf-8");
    const swaggerJson = JSON.parse(swaggerContent);
    
    // Update server URL based on environment
    if (process.env.FUNCTIONS_EMULATOR) {
      swaggerJson.servers = [
        {
          url: "http://localhost:5001/canma-wallet/us-central1/api",
          description: "Local emulator",
        },
      ];
    }
    
    res.setHeader("Content-Type", "application/json");
    res.status(200).json(swaggerJson);
  } catch (error) {
    console.error("Error serving Swagger:", error);
    res.status(500).json({
      error: "Failed to load Swagger documentation",
    });
  }
});

/**
 * API Info Endpoint
 * GET / - Returns API information and available endpoints
 */
app.get("/", (req, res) => {
  res.json({
    name: "Canma Wallet API",
    version: "1.0.0",
    description: "Lisk Crypto Banking API dengan Web3Auth + Firebase",
    endpoints: {
      login: "POST /login",
      register: "POST /register",
      verifyPin: "POST /verify-pin",
      createQRIS: "POST /create-qris",
      getBalance: "GET /balance/:walletAddress",
      swagger: "GET /swagger.json",
      webhook: "POST /xendit-webhook",
    },
    documentation: "/swagger.json",
    swaggerUI: "https://editor.swagger.io/?url=" + req.protocol + "://" + req.get("host") + "/swagger.json",
  });
});

// Export as single HTTP function
export const api = functions.https.onRequest(app);

// ============ USER SEARCH ENDPOINTS ============

/**
 * Search users by name or email
 * GET /users/search?q=query
 * Returns list of users with wallet addresses (for Split Bill, P2P payments)
 */
app.get("/users/search", async (req, res) => {
  try {
    const query = (req.query.q as string || "").toLowerCase().trim();
    
    if (!query || query.length < 2) {
      return res.status(400).json({
        success: false,
        error: "Search query must be at least 2 characters",
      });
    }

    // Search users in Firestore
    const usersSnapshot = await db.collection("users").get();
    const results: any[] = [];

    usersSnapshot.forEach((doc) => {
      const data = doc.data();
      const walletAddress = data.wallet_address || data.walletAddress;
      
      // Only include users with wallet addresses
      if (!walletAddress) return;
      
      const name = (data.name || "").toLowerCase();
      const email = (data.email || "").toLowerCase();
      
      // Match by name or email
      if (name.includes(query) || email.includes(query)) {
        results.push({
          uid: doc.id,
          name: data.name || "Unknown",
          email: data.email || "",
          walletAddress: walletAddress,
          photoURL: data.photoURL || null,
        });
      }
    });

    // Limit results
    const limitedResults = results.slice(0, 20);

    return res.status(200).json({
      success: true,
      data: limitedResults,
      total: results.length,
    });
  } catch (error) {
    console.error("User search error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Search failed",
    });
  }
});

/**
 * Get all registered users with wallet addresses
 * GET /users/registered
 * Returns list of all users who have wallet addresses
 */
app.get("/users/registered", async (req, res) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50;
    
    const usersSnapshot = await db.collection("users").get();
    const results: any[] = [];

    usersSnapshot.forEach((doc) => {
      const data = doc.data();
      const walletAddress = data.wallet_address || data.walletAddress;
      
      if (walletAddress) {
        results.push({
          uid: doc.id,
          name: data.name || "Unknown",
          email: data.email || "",
          walletAddress: walletAddress,
          photoURL: data.photoURL || null,
        });
      }
    });

    // Sort by name and limit
    results.sort((a, b) => a.name.localeCompare(b.name));
    const limitedResults = results.slice(0, limit);

    return res.status(200).json({
      success: true,
      data: limitedResults,
      total: results.length,
    });
  } catch (error) {
    console.error("Get registered users error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Failed to get users",
    });
  }
});

// ============ PRICE ENDPOINTS (CoinCap) ============

// GET /prices - Get token prices in USD
app.get("/prices", async (req, res) => {
  try {
    const symbols = (req.query.symbols as string)?.split(",") || ["POL", "ETH", "LSK"];
    const prices = await fetchPrices(symbols);
    res.json({
      success: true,
      prices,
      currency: "USD",
      timestamp: Date.now(),
    });
  } catch (error) {
    res.status(500).json({ success: false, error: "Failed to fetch prices" });
  }
});

// GET /prices/idr - Get token prices in IDR
app.get("/prices/idr", async (req, res) => {
  try {
    const symbols = (req.query.symbols as string)?.split(",") || ["POL", "ETH", "LSK"];
    const prices = await fetchPricesIDR(symbols);
    res.json({
      success: true,
      prices,
      currency: "IDR",
      usdToIdr: getUsdToIdr(),
      timestamp: Date.now(),
    });
  } catch (error) {
    res.status(500).json({ success: false, error: "Failed to fetch prices" });
  }
});

// POST /total-balance - Calculate total balance in IDR
app.post("/total-balance", async (req, res) => {
  try {
    const { balances } = req.body;
    // balances: [{ symbol: "POL", balance: 11.8 }, { symbol: "ETH", balance: 0.5 }]
    
    if (!balances || !Array.isArray(balances)) {
      res.status(400).json({ success: false, error: "balances array required" });
      return;
    }

    const result = await calculateTotalBalanceIDR(balances);
    res.json({
      success: true,
      ...result,
      usdToIdr: getUsdToIdr(),
      timestamp: Date.now(),
    });
  } catch (error) {
    res.status(500).json({ success: false, error: "Failed to calculate total" });
  }
});

// ============ QRIS PAYMENT ENDPOINTS ============

// POST /qris/payments - Create payment intent
app.post("/qris/payments", async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: "QRIS payment service not initialized. Check ESCROW_MASTER_MNEMONIC.",
      });
    }

    const { walletAddress, qrisPayload, amountIdr } = req.body;

    if (!walletAddress || !qrisPayload || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: "walletAddress, qrisPayload, and amountIdr are required",
      });
    }

    // Get current LSK price in IDR
    const pricesIdr = await fetchPricesIDR(["LSK"]);
    const lskPriceIdr = pricesIdr.LSK;

    if (!lskPriceIdr || lskPriceIdr <= 0) {
      return res.status(500).json({
        success: false,
        error: "Failed to fetch LSK price",
      });
    }

    const payment = await qrisPaymentService.createPayment(
      { walletAddress, qrisPayload, amountIdr },
      lskPriceIdr
    );

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error("[QRIS] Create payment error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Failed to create payment",
    });
  }
});

// GET /qris/payments/:paymentId - Get payment status
app.get("/qris/payments/:paymentId", async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: "QRIS payment service not initialized",
      });
    }

    const { paymentId } = req.params;
    const payment = qrisPaymentService.getPayment(paymentId);

    if (!payment) {
      return res.status(404).json({
        success: false,
        error: "Payment not found",
      });
    }

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error("[QRIS] Get payment error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Failed to get payment",
    });
  }
});

// POST /qris/payments/:paymentId/tx - Submit transaction hash
app.post("/qris/payments/:paymentId/tx", async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: "QRIS payment service not initialized",
      });
    }

    const { paymentId } = req.params;
    const { txHash } = req.body;

    if (!txHash) {
      return res.status(400).json({
        success: false,
        error: "txHash is required",
      });
    }

    const payment = await qrisPaymentService.submitTxHash(paymentId, txHash);

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error("[QRIS] Submit tx error:", error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Failed to submit transaction",
    });
  }
});

// ============ SPLIT BILL ROLE GRANT ============
const SPLIT_BILL_ESCROW_ADDRESS = '0xb7338a31BaE3b39170Cde6044695c444fc78E5F8';
const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE'));

const SPLIT_BILL_ABI = [
  'function grantRole(bytes32 role, address account) external',
  'function hasRole(bytes32 role, address account) view returns (bool)'
];

// Grant OPERATOR_ROLE to wallet for Split Bill
app.post('/splitbill/grant-role', async (req, res) => {
  try {
    const { walletAddress } = req.body;
    
    if (!walletAddress || !ethers.isAddress(walletAddress)) {
      return res.status(400).json({ success: false, error: 'Invalid wallet address' });
    }

    const adminPrivateKey = process.env.ADMIN_PRIVATE_KEY || process.env.PRIVATE_KEY;
    if (!adminPrivateKey) {
      return res.status(500).json({ success: false, error: 'Server not configured with admin key' });
    }

    const provider = new ethers.JsonRpcProvider('https://rpc.sepolia-api.lisk.com');
    const adminWallet = new ethers.Wallet(adminPrivateKey, provider);
    const contract = new ethers.Contract(SPLIT_BILL_ESCROW_ADDRESS, SPLIT_BILL_ABI, adminWallet);

    // Check if already has role
    const hasRole = await contract.hasRole(OPERATOR_ROLE, walletAddress);
    if (hasRole) {
      console.log(`[SplitBill] ${walletAddress} already has OPERATOR_ROLE`);
      return res.json({ success: true, message: 'Already has role', alreadyHasRole: true });
    }

    // Grant role
    console.log(`[SplitBill] Granting OPERATOR_ROLE to ${walletAddress}...`);
    const tx = await contract.grantRole(OPERATOR_ROLE, walletAddress);
    await tx.wait();

    console.log(`[SplitBill] OPERATOR_ROLE granted to ${walletAddress}, tx: ${tx.hash}`);
    return res.json({ success: true, message: 'Role granted', txHash: tx.hash });

  } catch (error: any) {
    console.error('[SplitBill] Grant role error:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// Check if wallet has OPERATOR_ROLE
app.get('/splitbill/check-role/:walletAddress', async (req, res) => {
  try {
    const { walletAddress } = req.params;
    
    if (!walletAddress || !ethers.isAddress(walletAddress)) {
      return res.status(400).json({ success: false, error: 'Invalid wallet address' });
    }

    const provider = new ethers.JsonRpcProvider('https://rpc.sepolia-api.lisk.com');
    const contract = new ethers.Contract(SPLIT_BILL_ESCROW_ADDRESS, SPLIT_BILL_ABI, provider);

    const hasRole = await contract.hasRole(OPERATOR_ROLE, walletAddress);
    return res.json({ success: true, hasRole, walletAddress });

  } catch (error: any) {
    console.error('[SplitBill] Check role error:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// ============ SPLIT BILL PAYMENT (Gas Sponsored) ============
const SIMPLE_SPLIT_BILL_ADDRESS = '0x49835BE16a3370Ea500ed35Ef66E0fC85206124F';
const LSK_TOKEN_ADDRESS = '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';

const SPLIT_BILL_PAYMENT_ABI = [
  'function payShare(bytes32 billId) external',
  'function getBill(bytes32 billId) view returns (tuple(bytes32 billId, address creator, string description, uint256 totalAmount, uint256 collectedAmount, uint256 createdAt, uint256 deadline, uint8 status, uint8 participantCount, uint8 paidCount))',
  'function getParticipantStatus(bytes32 billId, address user) view returns (bool isParticipant, uint256 amountDue, uint256 amountPaid, bool hasPaid)'
];

const ERC20_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function transferFrom(address from, address to, uint256 amount) returns (bool)'
];

// Send gas to user wallet for Split Bill operations
app.post('/splitbill/request-gas', async (req, res) => {
  try {
    const { walletAddress } = req.body;
    
    if (!walletAddress) {
      return res.status(400).json({ success: false, error: 'Missing walletAddress' });
    }

    const hotWalletKey = process.env.HOT_WALLET_PRIVATE_KEY;
    if (!hotWalletKey) {
      return res.status(500).json({ success: false, error: 'Hot wallet not configured' });
    }

    const provider = new ethers.JsonRpcProvider('https://rpc.sepolia-api.lisk.com');
    const hotWallet = new ethers.Wallet(hotWalletKey, provider);
    
    const userBalance = await provider.getBalance(walletAddress);
    const gasNeeded = ethers.parseEther('0.02'); // 0.02 ETH for gas
    
    console.log(`[SplitBill] User ${walletAddress} balance: ${ethers.formatEther(userBalance)} ETH`);
    
    if (userBalance >= gasNeeded) {
      return res.json({ 
        success: true, 
        message: 'User already has sufficient gas',
        gasSent: false,
        userBalance: userBalance.toString()
      });
    }

    const amountToSend = gasNeeded - userBalance + ethers.parseEther('0.005');
    console.log(`[SplitBill] Sending ${ethers.formatEther(amountToSend)} ETH to ${walletAddress}...`);
    
    const gasTx = await hotWallet.sendTransaction({
      to: walletAddress,
      value: amountToSend,
    });
    await gasTx.wait();
    
    console.log(`[SplitBill] Gas sent: ${gasTx.hash}`);
    
    return res.json({ 
      success: true, 
      message: 'Gas sent to your wallet',
      gasSent: true,
      txHash: gasTx.hash,
      amountSent: amountToSend.toString()
    });

  } catch (error: any) {
    console.error('[SplitBill] Request gas error:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// Pay Split Bill share with gas sponsorship
app.post('/splitbill/pay', async (req, res) => {
  try {
    const { billId, payerAddress } = req.body;
    
    if (!billId || !payerAddress) {
      return res.status(400).json({ success: false, error: 'Missing billId or payerAddress' });
    }

    const hotWalletKey = process.env.HOT_WALLET_PRIVATE_KEY;
    if (!hotWalletKey) {
      return res.status(500).json({ success: false, error: 'Hot wallet not configured' });
    }

    const provider = new ethers.JsonRpcProvider('https://rpc.sepolia-api.lisk.com');
    const hotWallet = new ethers.Wallet(hotWalletKey, provider);
    
    const splitBillContract = new ethers.Contract(SIMPLE_SPLIT_BILL_ADDRESS, SPLIT_BILL_PAYMENT_ABI, hotWallet);
    const tokenContract = new ethers.Contract(LSK_TOKEN_ADDRESS, ERC20_ABI, provider);

    console.log(`[SplitBill] Processing payment for bill ${billId} from ${payerAddress}`);

    // Check participant status
    const [isParticipant, amountDue, , hasPaid] = await splitBillContract.getParticipantStatus(billId, payerAddress);
    
    if (!isParticipant) {
      return res.status(400).json({ success: false, error: 'Not a participant in this bill' });
    }
    
    if (hasPaid) {
      return res.status(400).json({ success: false, error: 'Already paid' });
    }

    console.log(`[SplitBill] Amount due: ${ethers.formatEther(amountDue)} LSK`);

    // Check if user has approved the contract
    const allowance = await tokenContract.allowance(payerAddress, SIMPLE_SPLIT_BILL_ADDRESS);
    console.log(`[SplitBill] Current allowance: ${ethers.formatEther(allowance)} LSK`);

    if (allowance < amountDue) {
      return res.status(400).json({ 
        success: false, 
        error: 'Insufficient allowance. Please approve tokens first.',
        requiredAllowance: amountDue.toString(),
        currentAllowance: allowance.toString()
      });
    }

    // Execute payShare with hot wallet paying for gas
    console.log(`[SplitBill] Executing payShare with hot wallet gas...`);
    
    // We need to call payShare as the payer, not hot wallet
    // Since payShare uses msg.sender, we need the user to sign the tx
    // Alternative: Use permit or meta-transaction pattern
    
    // For now, send ETH to user for gas
    const gasNeeded = ethers.parseEther('0.01'); // 0.01 ETH for gas
    const userBalance = await provider.getBalance(payerAddress);
    
    if (userBalance < gasNeeded) {
      console.log(`[SplitBill] Sending gas to ${payerAddress}...`);
      const gasTx = await hotWallet.sendTransaction({
        to: payerAddress,
        value: gasNeeded - userBalance + ethers.parseEther('0.005'), // Extra buffer
      });
      await gasTx.wait();
      console.log(`[SplitBill] Gas sent: ${gasTx.hash}`);
    }

    return res.json({ 
      success: true, 
      message: 'Gas sent to your wallet. Please retry the payment.',
      gasSent: true,
      billId,
      amountDue: amountDue.toString()
    });

  } catch (error: any) {
    console.error('[SplitBill] Payment error:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// ============ SCHEDULED FUNCTIONS ============
// Note: For auto deposit listener, use the /run-listener endpoint manually
// or set up a Cloud Scheduler job to call it periodically.
// Firebase Functions v2 scheduled functions require additional setup.

// ============ STANDALONE SERVER ============
// Run as standalone Express server when not in Firebase Functions environment
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`[Server] Backend running on http://0.0.0.0:${PORT}`);
  console.log(`[Server] API endpoints available:`);
  console.log(`  - GET  /api/info`);
  console.log(`  - POST /login`);
  console.log(`  - POST /register`);
  console.log(`  - GET  /balance/:walletAddress`);
  console.log(`  - GET  /users/search?q=query`);
  console.log(`  - GET  /users/registered`);
  console.log(`  - POST /qris/create`);
});
