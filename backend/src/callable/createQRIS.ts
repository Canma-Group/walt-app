import {CallableRequest} from "firebase-functions/v2/https";
import {createQRISPayment as generateQRIS, CreateQRISParams} from "../services/onrampService";
import {db} from "../config/firebase";

/**
 * Callable Function: Create QRIS Payment
 * Called from Flutter app when user wants to top-up
 */

export const createQRISPayment = async (request: CallableRequest) => {
  // Get authenticated user
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("Unauthorized: User must be logged in");
  }

  // Validate request data
  const {amountInIDR, userWalletAddress} = request.data as CreateQRISParams;

  if (!amountInIDR || amountInIDR < 10000) {
    throw new Error("Minimum top-up amount is Rp 10,000");
  }

  if (!userWalletAddress || !userWalletAddress.startsWith("0x")) {
    throw new Error("Invalid wallet address");
  }

  try {
    // 🆕 AUTO-SAVE WALLET ADDRESS TO FIRESTORE (Opsi C - Hybrid)
    await db.collection("users").doc(uid).set({
      walletAddress: userWalletAddress,
      lastActivity: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }, {merge: true});  // merge: true = tidak overwrite data existing

    const qrisResponse = await generateQRIS({
      amountInIDR,
      userId: uid,
      userWalletAddress,
    });

    return {
      success: true,
      data: qrisResponse,
    };
  } catch (error) {
    console.error("Error creating QRIS:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
};


