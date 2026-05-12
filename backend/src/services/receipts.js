// Phase 13.3.3 — PDF receipts.
//
// Generates a printable / downloadable PDF receipt for any completed order.
// Used by:
//   • Email receipts to buyers (Phase 12 Resend integration).
//   • Shop owner downloading from the dashboard for accounting / VAT records.
//   • Tax authorities — paired with the Soliq.uz fiscal QR (Phase 13.3.9).
//
// Public API:
//   generateReceipt(orderId) -> Promise<Buffer>
//
// Implementation notes:
//   • Built on `pdfkit` — the standard Node PDF library. No native deps; tiny
//     install footprint. Uses built-in Helvetica family so we don't ship a
//     custom font yet (Cyrillic + Latin renders fine).
//   • Returns a Buffer — caller decides whether to stream it directly to an
//     HTTP response, attach to an email, or persist to object storage.
//   • Fiscal QR: when the order has a Soliq.uz `fiscalReceiptUrl`, we encode
//     it as a QR placeholder block at the bottom. Real QR rendering is a
//     follow-up (needs `qrcode` dep) — for now we draw a styled box with the
//     URL so the receipt is still valid documentation.
//   • Locale: not used here. We render Cyrillic labels (Russian) because
//     that's the operator-facing language and what Uzbek tax inspectors
//     expect. A future enhancement can branch on buyer.locale.

const PDFDocument = require('pdfkit');
const prisma = require('../db');
const logger = require('../lib/logger');

// ─── Helpers ────────────────────────────────────────────────────────────────

function fmtMoney(amount, currency) {
  const n = Number(amount) || 0;
  // Thousands grouped by space (matches Uzbek convention: "150 000 UZS").
  const intStr = Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return `${intStr} ${currency || 'UZS'}`;
}

function fmtDate(d) {
  if (!d) return '—';
  const date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '—';
  const pad = (n) => String(n).padStart(2, '0');
  return (
    `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}

function paymentLabel(method) {
  switch (method) {
    case 'click':    return 'Click';
    case 'payme':    return 'Payme';
    case 'uzumpay':  return 'Uzum Pay';
    case 'kaspi':    return 'Kaspi';
    case 'cash':     return 'Наличные';
    default:         return method || '—';
  }
}

// ─── Order fetcher ──────────────────────────────────────────────────────────

async function fetchOrderForReceipt(orderId) {
  return prisma.order.findUnique({
    where: { id: orderId },
    include: {
      items: true,
      shop: true,
      buyer: { select: { id: true, name: true, phone: true, email: true } },
    },
  });
}

// ─── PDF builder ────────────────────────────────────────────────────────────

function buildPdf(order) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: 'A4',
        margins: { top: 50, bottom: 50, left: 50, right: 50 },
        info: {
          Title: `TezKetKaz receipt ${order.orderNumber || order.id}`,
          Author: 'TezKetKaz',
          Subject: `Order ${order.orderNumber || order.id} receipt`,
          Creator: 'TezKetKaz backend',
        },
      });

      const chunks = [];
      doc.on('data', (b) => chunks.push(b));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      // ─── Header ──────────────────────────────────────────────────────────
      doc.fontSize(20).fillColor('#000').text('TezKetKaz', { align: 'left' });
      doc.fontSize(10).fillColor('#666').text('Сервис экспресс-доставки', { align: 'left' });
      doc.moveDown(0.5);

      // Order metadata block (right-aligned id + date).
      const headerY = doc.y;
      doc.fontSize(11).fillColor('#000');
      doc.text(`Чек № ${order.orderNumber || order.id}`, 350, headerY, {
        align: 'right',
      });
      doc.fontSize(9).fillColor('#666');
      doc.text(`Дата: ${fmtDate(order.createdAt)}`, 350, doc.y, {
        align: 'right',
      });

      // Reset x position.
      doc.moveDown(1.5);
      doc.fillColor('#000');

      // ─── Shop block ──────────────────────────────────────────────────────
      doc.fontSize(13).text('Магазин', 50, doc.y);
      doc.fontSize(10).fillColor('#333');
      doc.text(order.shop?.name || '—');
      if (order.shop?.address) doc.text(order.shop.address);
      if (order.shop?.phone)   doc.text(`Тел.: ${order.shop.phone}`);
      if (order.shop?.soliqInn) doc.text(`ИНН: ${order.shop.soliqInn}`);
      doc.moveDown(0.5);

      // ─── Buyer block ─────────────────────────────────────────────────────
      doc.fillColor('#000').fontSize(13).text('Покупатель');
      doc.fontSize(10).fillColor('#333');
      doc.text(order.customerName || order.buyer?.name || '—');
      if (order.customerPhone) doc.text(`Тел.: ${order.customerPhone}`);
      if (order.deliveryAddress) doc.text(`Адрес: ${order.deliveryAddress}`);
      doc.moveDown(0.8);

      // ─── Items table ─────────────────────────────────────────────────────
      doc.fillColor('#000').fontSize(13).text('Состав заказа');
      doc.moveDown(0.3);

      const tableTop = doc.y;
      const col = {
        name: 50,
        qty: 320,
        price: 380,
        total: 480,
      };

      // Header row.
      doc.fontSize(10).fillColor('#666');
      doc.text('Наименование', col.name, tableTop);
      doc.text('Кол-во', col.qty, tableTop, { width: 50, align: 'right' });
      doc.text('Цена', col.price, tableTop, { width: 80, align: 'right' });
      doc.text('Сумма', col.total, tableTop, { width: 65, align: 'right' });
      doc.moveTo(50, tableTop + 14).lineTo(545, tableTop + 14).strokeColor('#ddd').stroke();
      doc.moveDown(1);

      // Body rows.
      doc.fillColor('#000');
      const currency = order.currency || 'UZS';
      let runningY = doc.y;
      const items = Array.isArray(order.items) ? order.items : [];
      for (const item of items) {
        const rowY = runningY;
        const qty = Number(item.quantity) || 0;
        const unitPrice = Number(item.price) || 0;
        const lineTotal = Number(item.total) || qty * unitPrice;
        doc.fontSize(10);
        doc.text(item.productName || '—', col.name, rowY, { width: 260 });
        doc.text(String(qty), col.qty, rowY, { width: 50, align: 'right' });
        doc.text(fmtMoney(unitPrice, currency), col.price, rowY, { width: 80, align: 'right' });
        doc.text(fmtMoney(lineTotal, currency), col.total, rowY, { width: 65, align: 'right' });
        // Row height fixed (pdfkit returns to caret after text; manually
        // advance so multiline product names don't overlap).
        runningY = Math.max(doc.y, rowY + 18);
        doc.y = runningY;
      }

      doc.moveTo(50, runningY + 4).lineTo(545, runningY + 4).strokeColor('#ddd').stroke();
      doc.y = runningY + 12;

      // ─── Totals block (right-aligned) ────────────────────────────────────
      const totalsX = 350;
      const valueWidth = 195;

      function totalRow(label, value, opts = {}) {
        const y = doc.y;
        doc.fontSize(opts.bold ? 11 : 10);
        doc.fillColor(opts.bold ? '#000' : '#333');
        doc.text(label, totalsX, y, { width: 130 });
        doc.text(value, totalsX + 130, y, { width: valueWidth - 130, align: 'right' });
        doc.moveDown(0.3);
      }

      totalRow('Подытог:', fmtMoney(order.subtotal, currency));
      if (Number(order.deliveryFee) > 0) {
        totalRow('Доставка:', fmtMoney(order.deliveryFee, currency));
      }
      if (Number(order.discount) > 0) {
        totalRow('Скидка:', `−${fmtMoney(order.discount, currency)}`);
      }
      if (Number(order.taxAmount) > 0) {
        const ratePct = (Number(order.taxRate) || 0) * 100;
        totalRow(
          `НДС (${ratePct.toFixed(0)}%):`,
          fmtMoney(order.taxAmount, currency),
        );
      }
      if (Number(order.tipAmount) > 0) {
        totalRow('Чаевые:', fmtMoney(order.tipAmount, currency));
      }
      totalRow('Итого:', fmtMoney(order.total, currency), { bold: true });

      doc.moveDown(0.8);

      // ─── Payment ─────────────────────────────────────────────────────────
      doc.fillColor('#000').fontSize(11).text(
        `Способ оплаты: ${paymentLabel(order.paymentMethod)}` +
        (order.isPaid ? ' (оплачено)' : ' (не оплачено)'),
        50,
        doc.y,
      );

      doc.moveDown(0.5);

      // ─── Fiscal block ────────────────────────────────────────────────────
      if (order.fiscalReceiptUrl || order.fiscalReceiptId) {
        doc.fontSize(12).fillColor('#000').text('Фискальный чек Soliq.uz');
        doc.fontSize(9).fillColor('#666');
        if (order.fiscalReceiptId) {
          doc.text(`ID: ${order.fiscalReceiptId}`);
        }
        if (order.fiscalReceiptUrl) {
          doc.text(order.fiscalReceiptUrl, { link: order.fiscalReceiptUrl, underline: true });
        }
        // Reserve a 100×100 placeholder for the QR (rendered as a styled
        // box; real QR encoding is a follow-up that needs the `qrcode`
        // dependency).
        const qrTop = doc.y + 8;
        doc.lineWidth(1).strokeColor('#000').rect(50, qrTop, 100, 100).stroke();
        doc.fontSize(8).fillColor('#999').text('QR', 50, qrTop + 44, {
          width: 100,
          align: 'center',
        });
        doc.y = qrTop + 110;
      }

      // ─── Footer ──────────────────────────────────────────────────────────
      const footerY = 770;
      doc.fontSize(8).fillColor('#888').text(
        'TezKetKaz — Условия возврата: https://tezketkaz.uz/legal/refund-policy',
        50,
        footerY,
        { width: 495, align: 'center' },
      );
      doc.text(
        'Поддержка: support@tezketkaz.uz   •   Этот документ сгенерирован автоматически.',
        50,
        footerY + 12,
        { width: 495, align: 'center' },
      );

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

// ─── Public API ─────────────────────────────────────────────────────────────

async function generateReceipt(orderId) {
  if (!orderId) throw new Error('orderId is required');
  const order = await fetchOrderForReceipt(orderId);
  if (!order) {
    const err = new Error('order_not_found');
    err.status = 404;
    throw err;
  }
  try {
    const buf = await buildPdf(order);
    return buf;
  } catch (err) {
    logger.error({ err: err.message, orderId }, 'receipt PDF build failed');
    throw err;
  }
}

module.exports = {
  generateReceipt,
  // Exposed for tests; not part of the stable public surface.
  _fmtMoney: fmtMoney,
  _fmtDate: fmtDate,
};
