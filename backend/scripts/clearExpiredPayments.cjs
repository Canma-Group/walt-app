const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function clearExpiredPayments() {
  try {
    // Mark all expired pending payments as EXPIRED
    const result = await pool.query(`
      UPDATE payment_intents 
      SET status = 'EXPIRED' 
      WHERE status IN ('CREATED', 'TX_SUBMITTED') 
      AND expires_at < NOW()
    `);
    console.log('Cleared expired payments:', result.rowCount);
    
    // Show remaining pending
    const pending = await pool.query(`
      SELECT payment_id, status, expires_at 
      FROM payment_intents 
      WHERE status IN ('CREATED', 'TX_SUBMITTED')
    `);
    console.log('Remaining pending:', pending.rowCount);
  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    await pool.end();
  }
}

clearExpiredPayments();
