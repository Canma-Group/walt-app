import {generateExternalId} from "../config/xendit";
import {db} from "../config/firebase";

/**
 * OnRamp Service - Manages fiat-to-crypto conversions via Xendit QRIS
 */

export interface CreateQRISParams {
  amountInIDR: number;
  userId: string;
  userWalletAddress: string;
}

export interface QRISResponse {
  qrisUrl: string;
  externalId: string;
  amount: number;
  expiresAt: string;
}

// Create QRIS payment for user
export const createQRISPayment = async (
  params: CreateQRISParams
): Promise<QRISResponse> => {
  const {amountInIDR, userId, userWalletAddress} = params;

  try {
    const externalId = generateExternalId(userId);

    // Create QRIS with Xendit
    // Note: For MVP, we'll create QRIS data structure
    // In production, integrate with actual Xendit API
    const qrisData = {
      id: externalId,
      qr_string: `https://api.xendit.co/qr_codes/${externalId}`,  // Mock URL for now
      external_id: externalId,
      amount: amountInIDR,
      status: "ACTIVE",
    };

    // TODO: Replace with actual Xendit API call when API key is configured
    // const qrisData = await xenditClient.QRCode.createQRCode({...});

    // Save to Firestore for tracking
    await db.collection("payments").doc(externalId).set({
      userId,
      userWalletAddress,
      amountIDR: amountInIDR,
      externalId,
      qrisId: qrisData.id,
      status: "pending",
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(), // 1 hour
    });

    return {
      qrisUrl: qrisData.qr_string,
      externalId,
      amount: amountInIDR,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    };
  } catch (error) {
    console.error("❌ Failed to create QRIS:", error);
    throw new Error(`QRIS creation failed: ${error}`);
  }
};


