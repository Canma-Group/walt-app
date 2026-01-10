import * as admin from "firebase-admin";
import * as dotenv from "dotenv";

// Load environment variables
dotenv.config();

// Firebase project ID
const projectId = process.env.FIREBASE_PROJECT_ID || "canma-wallet";

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  // Check if we have service account credentials
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  
  if (serviceAccountPath) {
    // Use service account file
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: projectId,
    });
    console.log('[Firebase] Initialized with service account');
  } else {
    // Initialize with project ID only (for environments with default credentials)
    admin.initializeApp({
      projectId: projectId,
    });
    console.log('[Firebase] Initialized with project ID:', projectId);
  }
}

// Export initialized instances
export const db = admin.firestore();
export const auth = admin.auth();

// Firebase configuration
export const FIREBASE_CONFIG = {
  projectId: projectId,
};


