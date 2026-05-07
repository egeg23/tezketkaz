const ms = require('../src/lib/ms');

describe('ms() duration parser', () => {
  test('numeric pass-through', () => {
    expect(ms(1000)).toBe(1000);
  });
  test('seconds, minutes, hours, days', () => {
    expect(ms('15s')).toBe(15_000);
    expect(ms('5m')).toBe(300_000);
    expect(ms('1h')).toBe(3_600_000);
    expect(ms('30d')).toBe(30 * 86_400_000);
  });
  test('whitespace tolerant', () => {
    expect(ms('  10s  ')).toBe(10_000);
  });
  test('default unit is ms', () => {
    expect(ms('500')).toBe(500);
  });
  test('invalid throws', () => {
    expect(() => ms('lol')).toThrow();
  });
});
