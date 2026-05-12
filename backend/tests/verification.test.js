// Phase 6.5 — KYC verification document tests.
//
// Covers:
//   1. Upload with valid mimetype → pending row inserted.
//   2. Reject with reason → status=rejected, rejectionReason set.
//   3. Approve all required docs → courier auto-promoted.
//   4. Non-admin POSTs to admin endpoints → 403.

const request = require('supertest');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');
const { REQUIRED_COURIER_DOCS } = require('../src/routes/verification');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('verification');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

// Smallest possible valid PNG (1x1 transparent), used as upload payload.
const PNG_1x1 = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4' +
  '890000000d49444154789c63f8cf00000000010001036e0a0c0000000049454e44ae426082',
  'hex',
);

function tmpPng() {
  const p = path.join(os.tmpdir(), `verif-${Date.now()}-${Math.random().toString(36).slice(2)}.png`);
  fs.writeFileSync(p, PNG_1x1);
  return p;
}

describe('POST /api/verification/upload', () => {
  test('valid mimetype → pending row inserted', async () => {
    const u = await createUser(prisma);
    const file = tmpPng();
    const res = await request(ctx.app)
      .post('/api/verification/upload')
      .set('Authorization', u.auth)
      .field('type', 'passport_front')
      .attach('file', file);
    fs.unlinkSync(file);

    expect(res.status).toBe(201);
    expect(res.body.doc).toEqual(expect.objectContaining({
      userId: u.user.id,
      type: 'passport_front',
      status: 'pending',
    }));
    expect(res.body.doc.url).toMatch(/^\/uploads\/verification\//);

    const stored = await prisma.verificationDocument.findUnique({ where: { id: res.body.doc.id } });
    expect(stored).toBeTruthy();
    expect(stored.status).toBe('pending');
  });

  test('missing/invalid type → 400', async () => {
    const u = await createUser(prisma);
    const file = tmpPng();
    const res = await request(ctx.app)
      .post('/api/verification/upload')
      .set('Authorization', u.auth)
      .field('type', 'not_a_type')
      .attach('file', file);
    fs.unlinkSync(file);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/verification/me', () => {
  test('returns only the caller\'s docs', async () => {
    const a = await createUser(prisma);
    const b = await createUser(prisma);
    await prisma.verificationDocument.createMany({
      data: [
        { userId: a.user.id, type: 'selfie', url: '/uploads/verification/a.png' },
        { userId: b.user.id, type: 'selfie', url: '/uploads/verification/b.png' },
      ],
    });
    const res = await request(ctx.app)
      .get('/api/verification/me')
      .set('Authorization', a.auth);
    expect(res.status).toBe(200);
    expect(res.body.docs.every((d) => d.userId === a.user.id)).toBe(true);
  });
});

describe('admin reject', () => {
  test('reject with reason → status=rejected, rejectionReason set', async () => {
    const admin = await createUser(prisma, { isAdmin: true });
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'passport_front', url: '/x.png' },
    });
    const res = await request(ctx.app)
      .post(`/api/admin/verification/${doc.id}/reject`)
      .set('Authorization', admin.auth)
      .send({ reason: 'blurry photo' });
    expect(res.status).toBe(200);
    expect(res.body.doc.status).toBe('rejected');
    expect(res.body.doc.rejectionReason).toBe('blurry photo');
    expect(res.body.doc.reviewedById).toBe(admin.user.id);
  });

  test('reject without reason → 400', async () => {
    const admin = await createUser(prisma, { isAdmin: true });
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'passport_front', url: '/x.png' },
    });
    const res = await request(ctx.app)
      .post(`/api/admin/verification/${doc.id}/reject`)
      .set('Authorization', admin.auth)
      .send({});
    expect(res.status).toBe(400);
  });
});

describe('admin approve + courier auto-promote', () => {
  test('approve all required docs → courier auto-promoted', async () => {
    const admin = await createUser(prisma, { isAdmin: true });
    const u = await createUser(prisma);
    expect(u.user.courierStatus).toBe('none');
    expect(u.user.isCourier).toBe(false);

    // Create one pending doc per required type, approve them in order.
    const ids = [];
    for (const type of REQUIRED_COURIER_DOCS) {
      const doc = await prisma.verificationDocument.create({
        data: { userId: u.user.id, type, url: `/uploads/verification/${type}.png` },
      });
      ids.push(doc.id);
    }
    for (let i = 0; i < ids.length; i++) {
      const res = await request(ctx.app)
        .post(`/api/admin/verification/${ids[i]}/approve`)
        .set('Authorization', admin.auth)
        .send();
      expect(res.status).toBe(200);
      expect(res.body.doc.status).toBe('approved');
      // Promotion happens only on the LAST doc.
      if (i === ids.length - 1) {
        expect(res.body.courierPromoted).toBe(true);
      } else {
        expect(res.body.courierPromoted).toBe(false);
      }
    }
    const after = await prisma.user.findUnique({ where: { id: u.user.id } });
    expect(after.courierStatus).toBe('approved');
    expect(after.isCourier).toBe(true);
  });
});

describe('non-admin guards', () => {
  test('non-admin POST /api/admin/verification/:id/approve → 403', async () => {
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'selfie', url: '/x.png' },
    });
    const res = await request(ctx.app)
      .post(`/api/admin/verification/${doc.id}/approve`)
      .set('Authorization', u.auth)
      .send();
    expect(res.status).toBe(403);
  });

  test('non-admin POST /api/admin/verification/:id/reject → 403', async () => {
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'selfie', url: '/x.png' },
    });
    const res = await request(ctx.app)
      .post(`/api/admin/verification/${doc.id}/reject`)
      .set('Authorization', u.auth)
      .send({ reason: 'no' });
    expect(res.status).toBe(403);
  });

  test('non-admin GET /api/admin/verification → 403', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .get('/api/admin/verification')
      .set('Authorization', u.auth);
    expect(res.status).toBe(403);
  });
});

describe('PUT /api/verification/:id — Phase 13.2.4 re-upload', () => {
  test('replace rejected doc → status returns to pending and reason is cleared', async () => {
    const admin = await createUser(prisma, { isAdmin: true });
    const u = await createUser(prisma);

    // 1) Upload an initial doc.
    const file1 = tmpPng();
    const up = await request(ctx.app)
      .post('/api/verification/upload')
      .set('Authorization', u.auth)
      .field('type', 'passport_front')
      .attach('file', file1);
    fs.unlinkSync(file1);
    expect(up.status).toBe(201);
    const docId = up.body.doc.id;

    // 2) Admin rejects it.
    const rej = await request(ctx.app)
      .post(`/api/admin/verification/${docId}/reject`)
      .set('Authorization', admin.auth)
      .send({ reason: 'blurry' });
    expect(rej.status).toBe(200);
    expect(rej.body.doc.status).toBe('rejected');

    // 3) Owner re-uploads via PUT.
    const file2 = tmpPng();
    const replace = await request(ctx.app)
      .put(`/api/verification/${docId}`)
      .set('Authorization', u.auth)
      .attach('file', file2);
    fs.unlinkSync(file2);

    expect(replace.status).toBe(200);
    expect(replace.body.doc.id).toBe(docId);
    expect(replace.body.doc.status).toBe('pending');
    expect(replace.body.doc.rejectionReason).toBeNull();
    expect(replace.body.doc.reviewedById).toBeNull();
    expect(replace.body.doc.reviewedAt).toBeNull();
    expect(replace.body.doc.url).toMatch(/^\/uploads\/verification\//);
    // URL must point at a brand-new file, not the original.
    expect(replace.body.doc.url).not.toBe(up.body.doc.url);
  });

  test('admin sees the replaced doc as pending', async () => {
    const admin = await createUser(prisma, { isAdmin: true });
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: {
        userId: u.user.id,
        type: 'selfie',
        url: '/uploads/verification/old.png',
        status: 'rejected',
        rejectionReason: 'too dark',
      },
    });
    const file = tmpPng();
    const replace = await request(ctx.app)
      .put(`/api/verification/${doc.id}`)
      .set('Authorization', u.auth)
      .attach('file', file);
    fs.unlinkSync(file);
    expect(replace.status).toBe(200);

    const list = await request(ctx.app)
      .get('/api/admin/verification?status=pending')
      .set('Authorization', admin.auth);
    expect(list.status).toBe(200);
    const ids = list.body.docs.map((d) => d.id);
    expect(ids).toContain(doc.id);
  });

  test('non-owner cannot replace someone else\'s doc → 403', async () => {
    const a = await createUser(prisma);
    const b = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: {
        userId: a.user.id,
        type: 'selfie',
        url: '/uploads/verification/a.png',
        status: 'rejected',
        rejectionReason: 'nope',
      },
    });
    const file = tmpPng();
    const res = await request(ctx.app)
      .put(`/api/verification/${doc.id}`)
      .set('Authorization', b.auth)
      .attach('file', file);
    fs.unlinkSync(file);
    expect(res.status).toBe(403);
  });

  test('cannot replace pending doc → 409', async () => {
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: {
        userId: u.user.id,
        type: 'selfie',
        url: '/uploads/verification/p.png',
        status: 'pending',
      },
    });
    const file = tmpPng();
    const res = await request(ctx.app)
      .put(`/api/verification/${doc.id}`)
      .set('Authorization', u.auth)
      .attach('file', file);
    fs.unlinkSync(file);
    expect(res.status).toBe(409);
  });

  test('cannot replace approved doc → 409 (admin must reject first)', async () => {
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: {
        userId: u.user.id,
        type: 'selfie',
        url: '/uploads/verification/ok.png',
        status: 'approved',
      },
    });
    const file = tmpPng();
    const res = await request(ctx.app)
      .put(`/api/verification/${doc.id}`)
      .set('Authorization', u.auth)
      .attach('file', file);
    fs.unlinkSync(file);
    expect(res.status).toBe(409);
  });

  test('missing file → 400', async () => {
    const u = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: {
        userId: u.user.id,
        type: 'selfie',
        url: '/uploads/verification/x.png',
        status: 'rejected',
        rejectionReason: 'r',
      },
    });
    const res = await request(ctx.app)
      .put(`/api/verification/${doc.id}`)
      .set('Authorization', u.auth);
    expect(res.status).toBe(400);
  });
});

describe('user delete own pending doc', () => {
  test('owner can delete pending doc; cannot delete reviewed doc', async () => {
    const u = await createUser(prisma);
    const pending = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'selfie', url: '/uploads/verification/x.png' },
    });
    const approved = await prisma.verificationDocument.create({
      data: { userId: u.user.id, type: 'passport_back', url: '/uploads/verification/y.png', status: 'approved' },
    });

    const r1 = await request(ctx.app)
      .delete(`/api/verification/${pending.id}`)
      .set('Authorization', u.auth);
    expect(r1.status).toBe(200);
    expect(r1.body.deleted).toBe(true);

    const r2 = await request(ctx.app)
      .delete(`/api/verification/${approved.id}`)
      .set('Authorization', u.auth);
    expect(r2.status).toBe(409);
  });

  test('foreign user cannot delete', async () => {
    const a = await createUser(prisma);
    const b = await createUser(prisma);
    const doc = await prisma.verificationDocument.create({
      data: { userId: a.user.id, type: 'selfie', url: '/x.png' },
    });
    const res = await request(ctx.app)
      .delete(`/api/verification/${doc.id}`)
      .set('Authorization', b.auth);
    expect(res.status).toBe(403);
  });
});
