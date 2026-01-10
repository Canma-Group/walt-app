import {Request, Response} from "express";
import {db} from "../config/firebase";
import {
  transferLSKToUser,
  calculateLSKFromIDR,
} from "../services/walletService";

/**
 * Xendit Webhook Handler
 * Receives payment notifications from Xendit
 */

export const xenditWebhook = async (req: Request, res: Response) => {
  try {
    // Verify webhook (simplified - add proper signature verification in production)
    const webhookToken = req.headers["x-callback-token"];
    if (webhookToken !== process.env.XENDIT_CALLBACK_TOKEN) {
      console.warn("⚠️ Invalid webhook token");
      return res.status(401).json({error: "Unauthorized"});
    }

    const payload = req.body;
    console.log("📥 Xendit webhook received:", payload);

    const {external_id, status, amount} = payload;

    // Only process successful payments
    if (status !== "COMPLETED") {
      console.log(`⏳ Payment status: ${status}, skipping...`);
      return res.status(200).json({received: true});
    }

    // Get payment details from Firestore
    const paymentDoc = await db.collection("payments").doc(external_id).get();

    if (!paymentDoc.exists) {
      console.error("❌ Payment not found:", external_id);
      return res.status(404).json({error: "Payment not found"});
    }

    const paymentData = paymentDoc.data();

    // Check if already processed
    if (paymentData?.status === "completed") {
      console.log("✅ Payment already processed, skipping");
      return res.status(200).json({received: true, alreadyProcessed: true});
    }

    // Calculate LSK amount
    const lskAmount = calculateLSKFromIDR(amount);

    // Transfer LSK to user
    const txHash = await transferLSKToUser(
      paymentData?.userWalletAddress,
      lskAmount,
      external_id
    );

    // Update payment status
    await db.collection("payments").doc(external_id).update({
      status: "completed",
      lskAmount,
      txHash,
      completedAt: new Date().toISOString(),
    });

    console.log(`✅ Successfully processed payment ${external_id}`);

    return res.status(200).json({
      success: true,
      txHash,
      lskAmount,
    });
  } catch (error) {
    console.error("❌ Webhook processing error:", error);
    return res.status(500).json({
      error: error instanceof Error ? error.message : "Internal server error",
    });
  }
};


