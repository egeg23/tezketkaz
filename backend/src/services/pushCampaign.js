// Phase 10.3 — push notification campaign sender.
//
// Picks locale-specific title/body from the PushCampaign row, resolves the
// audience via audienceQuery, sends FCM via push.sendToUser, and tallies
// success/failure counts on the campaign.

const push = require('./push');
const audienceQuery = require('./audienceQuery');
const logger = require('../lib/logger');

const SUPPORTED_LOCALES = ['uz', 'ru', 'en', 'kk'];

function pickLocale(loc) {
  if (SUPPORTED_LOCALES.includes(loc)) return loc;
  return 'uz';
}

// Pull title/body for a given locale, falling back through ru → uz when the
// optional en/kk fields are unset on the campaign row.
function localizedContent(campaign, locale) {
  const wanted = pickLocale(locale);
  const title =
    (wanted === 'uz' && campaign.titleUz) ||
    (wanted === 'ru' && campaign.titleRu) ||
    (wanted === 'en' && (campaign.titleEn || campaign.titleRu || campaign.titleUz)) ||
    (wanted === 'kk' && (campaign.titleKk || campaign.titleRu || campaign.titleUz)) ||
    campaign.titleUz;
  const body =
    (wanted === 'uz' && campaign.bodyUz) ||
    (wanted === 'ru' && campaign.bodyRu) ||
    (wanted === 'en' && (campaign.bodyEn || campaign.bodyRu || campaign.bodyUz)) ||
    (wanted === 'kk' && (campaign.bodyKk || campaign.bodyRu || campaign.bodyUz)) ||
    campaign.bodyUz;
  return { title, body };
}

async function preview(prisma, audienceSpec) {
  const recipientCount = await audienceQuery.countAudience(prisma, audienceSpec);
  return { recipientCount };
}

async function send(prisma, campaignId, opts = {}) {
  const campaign = await prisma.pushCampaign.findUnique({ where: { id: campaignId } });
  if (!campaign) throw new Error('Campaign not found');
  if (campaign.status === 'sent') return campaign;
  if (campaign.status === 'cancelled') {
    throw new Error('Campaign is cancelled');
  }

  // Compare-and-set claim. Two callers can both pass the status checks above
  // and both proceed without this guard, double-sending the campaign.
  // updateMany returns count=0 when another caller claimed first.
  const claim = await prisma.pushCampaign.updateMany({
    where: { id: campaign.id, status: { in: ['draft', 'scheduled'] } },
    data: { status: 'sending' },
  });
  if (claim.count !== 1) {
    // Already claimed (race) or status changed underneath us.
    return { ok: false, reason: 'not_claimable', campaignId: campaign.id };
  }

  let users = [];
  try {
    users = await audienceQuery.resolveAudience(
      prisma,
      campaign.audienceQuery,
      { limit: opts.limit || 100000 },
    );
  } catch (err) {
    logger.warn({ err: err.message, campaignId }, 'audience resolution failed');
    await prisma.pushCampaign.update({
      where: { id: campaign.id },
      data: { status: 'failed' },
    });
    throw err;
  }

  let successCount = 0;
  let failureCount = 0;
  const dataPayload = { type: 'campaign', campaignId: campaign.id };
  if (campaign.deepLink) dataPayload.deepLink = campaign.deepLink;

  for (const u of users) {
    // Respect promo opt-out preference.
    let allow = true;
    if (u.notificationPrefs) {
      try {
        const prefs = JSON.parse(u.notificationPrefs);
        if (prefs.promo === false) allow = false;
      } catch { /* ignore */ }
    }
    if (!allow) {
      failureCount += 1;
      continue;
    }

    const { title, body } = localizedContent(campaign, u.locale);
    try {
      const result = await push.sendToUser(u.id, { title, body, data: dataPayload });
      const sent = (result && (result.sent || result.mock)) ? 1 : 0;
      if (sent > 0) successCount += 1;
      else failureCount += 1;
    } catch (err) {
      logger.warn({ err: err.message, userId: u.id }, 'campaign push failed');
      failureCount += 1;
    }
  }

  const recipientCount = users.length;
  const updated = await prisma.pushCampaign.update({
    where: { id: campaign.id },
    data: {
      status: 'sent',
      sentAt: new Date(),
      recipientCount,
      successCount,
      failureCount,
    },
  });

  return updated;
}

async function trackOpen(prisma, campaignId) {
  const campaign = await prisma.pushCampaign.findUnique({ where: { id: campaignId } });
  if (!campaign) return null;
  return prisma.pushCampaign.update({
    where: { id: campaignId },
    data: { openCount: { increment: 1 } },
  });
}

module.exports = {
  preview,
  send,
  trackOpen,
  _localizedContent: localizedContent,
};
