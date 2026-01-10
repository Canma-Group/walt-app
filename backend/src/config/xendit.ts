import Xendit from "xendit-node";
import * as dotenv from "dotenv";

dotenv.config();

// Initialize Xendit Client
const xenditApiKey = process.env.XENDIT_API_KEY || "";

if (!xenditApiKey || xenditApiKey.startsWith("xnd_development_")) {
  console.warn(
    "⚠️ Xendit API key not properly configured. Using development mode."
  );
}

export const xenditClient = new Xendit({
  secretKey: xenditApiKey,
});

// Xendit Configuration
export const XENDIT_CONFIG = {
  callbackToken: process.env.XENDIT_CALLBACK_TOKEN || "",
  webhookToken: process.env.XENDIT_WEBHOOK_TOKEN || "",
  externalIdPrefix: "CANMA-",
};

// Helper: Generate unique external ID
export const generateExternalId = (userId: string): string => {
  const timestamp = Date.now();
  return `${XENDIT_CONFIG.externalIdPrefix}${userId}-${timestamp}`;
};


