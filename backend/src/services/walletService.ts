import {sendLSK} from "../config/lisk";
import {db} from "../config/firebase";

/**
 * Wallet Service - Manages blockchain operations
 */

// Transfer LSK from hot wallet to user wallet
export const transferLSKToUser = async (
  userWalletAddress: string,
  amountInLSK: string,
  paymentId: string
): Promise<string> => {
  try {
    // Send LSK transaction
    const txHash = await sendLSK(userWalletAddress, amountInLSK);

    // Log transaction to Firestore
    await db.collection("transactions").add({
      type: "top-up",
      userWalletAddress,
      amount: amountInLSK,
      currency: "LSK",
      txHash,
      paymentId,
      status: "completed",
      timestamp: new Date().toISOString(),
    });

    console.log(
      `✅ Transferred ${amountInLSK} LSK to ${userWalletAddress}. TX: ${txHash}`
    );

    return txHash;
  } catch (error) {
    console.error("❌ Transfer failed:", error);
    throw new Error(`Transfer failed: ${error}`);
  }
};

// Calculate LSK amount from IDR
export const calculateLSKFromIDR = (amountInIDR: number): string => {
  const rateIDR = parseFloat(process.env.LSK_TO_IDR_RATE || "5000");
  const lskAmount = amountInIDR / rateIDR;
  return lskAmount.toFixed(6); // 6 decimal precision
};


