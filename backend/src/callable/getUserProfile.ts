import {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../config/firebase";

/**
 * Callable Function: Get User Profile
 * Returns user's wallet address and metadata from Firestore
 */

export const getUserProfile = async (request: CallableRequest) => {
  // Get authenticated user
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("Unauthorized: User must be logged in");
  }

  try {
    const userDoc = await db.collection("users").doc(uid).get();

    if (!userDoc.exists) {
      return {
        success: false,
        message: "User profile not found. Please complete a transaction first.",
        data: null,
      };
    }

    return {
      success: true,
      data: {
        userId: uid,
        ...userDoc.data(),
      },
    };
  } catch (error) {
    console.error("Error getting user profile:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
};

