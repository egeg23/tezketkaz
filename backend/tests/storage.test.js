// Phase 9 — storage abstraction tests.
//
// Local driver covers put/get/del/list/signedUrl/putFromMulterFile against the
// real filesystem under a temp directory. The S3 driver is exercised via a
// jest.mock of @aws-sdk/client-s3 — we just verify the right command was sent
// with the right args; we don't ship the SDK as a runtime dependency.

const fs = require('fs');
const os = require('os');
const path = require('path');

// Test-isolated upload root: the local driver resolves `<lib>/../../uploads`,
// i.e. `<repoRoot>/backend/uploads`. We don't redirect that — instead we just
// scope keys to a unique prefix per test run so files don't collide.
const RUN_PREFIX = `__storagetest_${process.pid}_${Date.now()}`;

let storage;
let _resetForTests;
let putFromMulterFile;

beforeAll(() => {
  // Make sure no S3 vars leak from the host shell into the local-driver tests.
  delete process.env.S3_BUCKET;
  delete process.env.S3_ACCESS_KEY;
  // Reload env + storage with the cleared vars.
  for (const k of Object.keys(require.cache)) {
    if (k.includes('/src/lib/storage') || k.includes('/src/config/env')) {
      delete require.cache[k];
    }
  }
  // eslint-disable-next-line global-require
  ({ storage, _resetForTests, putFromMulterFile } = require('../src/lib/storage'));
  _resetForTests();
});

afterAll(() => {
  // Best-effort cleanup of anything we wrote under the run prefix.
  const root = path.resolve(__dirname, '..', 'uploads', RUN_PREFIX);
  try { fs.rmSync(root, { recursive: true, force: true }); } catch { /* noop */ }
});

describe('local driver', () => {
  test('put + get roundtrip', async () => {
    const drv = storage();
    expect(drv.name).toBe('local');
    const body = Buffer.from('hello world', 'utf8');
    const result = await drv.put(`${RUN_PREFIX}/roundtrip.txt`, body, { contentType: 'text/plain' });
    expect(result.url).toBe(`/uploads/${RUN_PREFIX}/roundtrip.txt`);
    expect(result.key).toBe(`${RUN_PREFIX}/roundtrip.txt`);

    const got = await drv.get(`${RUN_PREFIX}/roundtrip.txt`);
    expect(got).toBeInstanceOf(Buffer);
    expect(got.toString('utf8')).toBe('hello world');
  });

  test('put creates nested directories', async () => {
    const drv = storage();
    const key = `${RUN_PREFIX}/deep/nested/path/file.bin`;
    const body = Buffer.from([1, 2, 3, 4]);
    await drv.put(key, body);
    const got = await drv.get(key);
    expect(Array.from(got)).toEqual([1, 2, 3, 4]);
  });

  test('del removes a file', async () => {
    const drv = storage();
    const key = `${RUN_PREFIX}/to-delete.txt`;
    await drv.put(key, Buffer.from('bye'));
    expect(await drv.get(key)).not.toBeNull();
    await drv.del(key);
    expect(await drv.get(key)).toBeNull();
    // Calling del again on a missing key is a noop.
    await drv.del(key);
  });

  test('list returns existing keys under a prefix', async () => {
    const drv = storage();
    await drv.put(`${RUN_PREFIX}/listdir/a.txt`, Buffer.from('a'));
    await drv.put(`${RUN_PREFIX}/listdir/sub/b.txt`, Buffer.from('b'));
    const items = await drv.list(`${RUN_PREFIX}/listdir`);
    const keys = items.map((i) => i.key).sort();
    expect(keys).toEqual([
      `${RUN_PREFIX}/listdir/a.txt`,
      `${RUN_PREFIX}/listdir/sub/b.txt`,
    ]);
    for (const item of items) {
      expect(typeof item.size).toBe('number');
      // Cross-realm-safe Date check (jest module cache can mint a different
      // Date constructor than the one in scope here).
      expect(Object.prototype.toString.call(item.modifiedAt)).toBe('[object Date]');
      expect(Number.isFinite(item.modifiedAt.getTime())).toBe(true);
    }
  });

  test('list with olderThan filters newer files', async () => {
    const drv = storage();
    await drv.put(`${RUN_PREFIX}/older/recent.txt`, Buffer.from('new'));
    // olderThan: 1 minute ago — file we just wrote should NOT be returned.
    const cutoff = new Date(Date.now() - 60 * 1000);
    const items = await drv.list(`${RUN_PREFIX}/older`, { olderThan: cutoff });
    expect(items).toHaveLength(0);

    // olderThan in the future ⇒ file qualifies.
    const future = new Date(Date.now() + 60 * 1000);
    const items2 = await drv.list(`${RUN_PREFIX}/older`, { olderThan: future });
    expect(items2.length).toBe(1);
  });

  test('signedUrl returns the public path for the local driver', () => {
    const drv = storage();
    expect(drv.signedUrl(`${RUN_PREFIX}/sign.txt`)).toBe(`/uploads/${RUN_PREFIX}/sign.txt`);
    // expiresIn argument is ignored — local URLs are stable.
    expect(drv.signedUrl(`${RUN_PREFIX}/sign.txt`, { expiresIn: 60 }))
      .toBe(`/uploads/${RUN_PREFIX}/sign.txt`);
  });

  test('putFromMulterFile reads disk file, writes to storage, leaves local copy', async () => {
    // Simulate a multer-on-disk handoff: write a tmp source file, then call
    // the helper and verify the bytes ended up under `<key>` in the local
    // driver. Because the active driver is `local`, the source should still
    // exist (S3-only branch unlinks).
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'multerfaux-'));
    const src = path.join(tmpDir, 'src.bin');
    fs.writeFileSync(src, Buffer.from('multer-bytes'));
    const fakeFile = { path: src, mimetype: 'application/octet-stream', filename: 'src.bin' };

    const key = `${RUN_PREFIX}/multer/copy.bin`;
    const result = await putFromMulterFile(fakeFile, key);
    expect(result.key).toBe(key);
    expect(result.url).toBe(`/uploads/${key}`);

    const got = await storage().get(key);
    expect(got.toString('utf8')).toBe('multer-bytes');
    // Local driver doesn't unlink the source.
    expect(fs.existsSync(src)).toBe(true);

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });
});

describe('s3 driver (mocked SDK)', () => {
  test('put issues PutObjectCommand with correct Bucket/Key/ContentType', async () => {
    // Reset the per-process module cache so we get a fresh storage module
    // that picks up the env vars + our jest.mock below.
    jest.resetModules();

    const sentCommands = [];
    const fakeSend = jest.fn(async (cmd) => {
      sentCommands.push(cmd);
      return {};
    });

    // Capture the args each Command was constructed with.
    function makeCmd(name) {
      return class {
        constructor(input) {
          this.__name = name;
          this.input = input;
        }
      };
    }

    jest.doMock('@aws-sdk/client-s3', () => ({
      S3Client: class {
        constructor(cfg) { this.cfg = cfg; }
        send(cmd) { return fakeSend(cmd); }
      },
      PutObjectCommand: makeCmd('Put'),
      GetObjectCommand: makeCmd('Get'),
      DeleteObjectCommand: makeCmd('Delete'),
      ListObjectsV2Command: makeCmd('List'),
    }), { virtual: true });

    process.env.S3_BUCKET = 'tezketkaz-test';
    process.env.S3_ENDPOINT = 'https://example.r2.cloudflarestorage.com';
    process.env.S3_REGION = 'auto';
    process.env.S3_ACCESS_KEY = 'AKIAFAKE';
    process.env.S3_SECRET_KEY = 'secretfake';
    process.env.S3_PUBLIC_BASE = 'https://cdn.example.com';

    // Re-import storage with S3 vars set.
    // eslint-disable-next-line global-require
    const mod = require('../src/lib/storage');
    mod._resetForTests();

    const drv = mod.storage();
    expect(drv.name).toBe('s3');

    const result = await drv.put('products/foo.jpg', Buffer.from('img'), { contentType: 'image/jpeg' });
    expect(result.key).toBe('products/foo.jpg');
    expect(result.url).toBe('https://cdn.example.com/products/foo.jpg');

    expect(sentCommands).toHaveLength(1);
    expect(sentCommands[0].__name).toBe('Put');
    expect(sentCommands[0].input).toMatchObject({
      Bucket: 'tezketkaz-test',
      Key: 'products/foo.jpg',
      ContentType: 'image/jpeg',
    });
    expect(sentCommands[0].input.Body).toBeInstanceOf(Buffer);
  });
});
