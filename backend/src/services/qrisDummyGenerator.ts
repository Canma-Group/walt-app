/**
 * QRIS Dummy Generator
 * Generates valid QRIS format QR codes for testing
 * Format follows EMV QRIS specification
 */

interface QrisData {
  merchantName: string;
  merchantCity: string;
  amount?: number;
  merchantId?: string;
  terminalId?: string;
}

/**
 * Generate a TLV (Tag-Length-Value) field for QRIS
 */
function tlv(tag: string, value: string): string {
  const length = value.length.toString().padStart(2, '0');
  return `${tag}${length}${value}`;
}

/**
 * Calculate CRC16-CCITT checksum for QRIS
 */
function calculateCRC16(data: string): string {
  let crc = 0xFFFF;
  const polynomial = 0x1021;

  for (let i = 0; i < data.length; i++) {
    const byte = data.charCodeAt(i);
    crc ^= (byte << 8);
    
    for (let j = 0; j < 8; j++) {
      if (crc & 0x8000) {
        crc = ((crc << 1) ^ polynomial) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }

  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/**
 * Generate a valid QRIS payload string
 */
export function generateQrisPayload(data: QrisData): string {
  let payload = '';

  // Tag 00: Payload Format Indicator (required, always "01")
  payload += tlv('00', '01');

  // Tag 01: Point of Initiation Method
  // "11" = Static QR (reusable)
  // "12" = Dynamic QR (one-time use)
  payload += tlv('01', data.amount ? '12' : '11');

  // Tag 26: Merchant Account Information (QRIS specific)
  let merchantAccountInfo = '';
  merchantAccountInfo += tlv('00', 'ID.CO.QRIS.WWW'); // Globally Unique Identifier
  merchantAccountInfo += tlv('01', data.merchantId || 'CANMA001'); // Merchant ID
  merchantAccountInfo += tlv('02', 'CANMA WALLET'); // Merchant Name in Account
  payload += tlv('26', merchantAccountInfo);

  // Tag 52: Merchant Category Code (5411 = Grocery Stores)
  payload += tlv('52', '5411');

  // Tag 53: Transaction Currency (360 = IDR)
  payload += tlv('53', '360');

  // Tag 54: Transaction Amount (optional, for dynamic QR)
  if (data.amount && data.amount > 0) {
    payload += tlv('54', data.amount.toString());
  }

  // Tag 55: Tip or Convenience Indicator (not used)
  // payload += tlv('55', '00');

  // Tag 58: Country Code
  payload += tlv('58', 'ID');

  // Tag 59: Merchant Name
  payload += tlv('59', data.merchantName.substring(0, 25));

  // Tag 60: Merchant City
  payload += tlv('60', data.merchantCity.substring(0, 15));

  // Tag 61: Postal Code (optional)
  payload += tlv('61', '12345');

  // Tag 62: Additional Data Field Template
  let additionalData = '';
  additionalData += tlv('05', data.terminalId || 'TERM001'); // Reference Label
  additionalData += tlv('07', 'CANMA'); // Terminal Label
  payload += tlv('62', additionalData);

  // Tag 63: CRC (must be last, calculated over entire payload including "6304")
  const crcInput = payload + '6304';
  const crc = calculateCRC16(crcInput);
  payload += tlv('63', crc);

  return payload;
}

/**
 * Parse a QRIS payload string back to data
 */
export function parseQrisPayload(payload: string): QrisData | null {
  try {
    const result: QrisData = {
      merchantName: '',
      merchantCity: '',
    };

    let index = 0;
    while (index < payload.length - 4) {
      const tag = payload.substring(index, index + 2);
      const lengthStr = payload.substring(index + 2, index + 4);
      const length = parseInt(lengthStr, 10);

      if (isNaN(length) || length <= 0 || index + 4 + length > payload.length) {
        break;
      }

      const value = payload.substring(index + 4, index + 4 + length);

      switch (tag) {
        case '54':
          result.amount = parseFloat(value);
          break;
        case '59':
          result.merchantName = value;
          break;
        case '60':
          result.merchantCity = value;
          break;
      }

      index += 4 + length;
    }

    return result;
  } catch (e) {
    console.error('[QrisDummy] Parse error:', e);
    return null;
  }
}

/**
 * Generate sample QRIS codes for testing
 */
export function generateSampleQrisCodes(): Array<{ name: string; payload: string; amount?: number }> {
  return [
    {
      name: 'Static QR - Warung Makan',
      payload: generateQrisPayload({
        merchantName: 'WARUNG MAKAN SEDERHANA',
        merchantCity: 'JAKARTA',
        merchantId: 'WMS001',
      }),
    },
    {
      name: 'Dynamic QR - Rp 10.000',
      payload: generateQrisPayload({
        merchantName: 'TOKO SERBA ADA',
        merchantCity: 'BANDUNG',
        merchantId: 'TSA001',
        amount: 10000,
      }),
      amount: 10000,
    },
    {
      name: 'Dynamic QR - Rp 50.000',
      payload: generateQrisPayload({
        merchantName: 'CAFE KOPI NIKMAT',
        merchantCity: 'SURABAYA',
        merchantId: 'CKN001',
        amount: 50000,
      }),
      amount: 50000,
    },
    {
      name: 'Dynamic QR - Rp 100.000',
      payload: generateQrisPayload({
        merchantName: 'RESTORAN PADANG',
        merchantCity: 'MEDAN',
        merchantId: 'RP001',
        amount: 100000,
      }),
      amount: 100000,
    },
    {
      name: 'Xendit Test Merchant',
      payload: generateQrisPayload({
        merchantName: 'XENDIT TEST MERCHANT',
        merchantCity: 'JAKARTA',
        merchantId: 'XENDIT001',
        amount: 25000,
      }),
      amount: 25000,
    },
  ];
}
