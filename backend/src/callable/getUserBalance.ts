import {CallableRequest} from "firebase-functions/v2/https";
import {getLSKBalance} from "../config/lisk";

/**
 * Callable Function: Get User Balance
 * Called from Flutter app to check LSK balance
 */

export const getUserBalance = async (request: CallableRequest) => {
  // Get authenticated user
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("Unauthorized: User must be logged in");
  }

  const {walletAddress} = request.data;

  if (!walletAddress || !walletAddress.startsWith("0x")) {
    throw new Error("Invalid wallet address");
  }

  try {
    const balance = await getLSKBalance(walletAddress);

    return {
      success: true,
      data: {
        balance: balance,
        currency: "LSK",
        walletAddress,
      },
    };
  } catch (error) {
    console.error("Error getting balance:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
};


