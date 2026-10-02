import { test } from "node:test"
import assert from "node:assert/strict"
import { randomBytes } from "node:crypto"
import { Gen } from "./load.mjs"

const bytes = (n) => Array.from(randomBytes(n))

test("character sets match the Prime Passwords desktop app", () => {
  assert.equal(Gen.HEX, "0123456789ABCDEF")
  assert.equal(Gen.ALNUM.length, 62)
  assert.equal(Gen.PRINTABLE.length, 94)
  // Printable is every ASCII character from ! (33) to ~ (126), in order.
  let all = ""
  for (let c = 33; c <= 126; c++) all += String.fromCharCode(c)
  assert.equal(Gen.PRINTABLE, all)
  assert.equal(Gen.ALNUM, all.replace(/[^0-9A-Za-z]/g, ""))
})

test("bits match the desktop app", () => {
  assert.deepEqual([...Gen.KINDS].map((k) => Math.round(Gen.bits(k))), [256, 413, 375])
})

test("accept limits are the largest multiple of the set size", () => {
  assert.equal(Gen.acceptLimit(16), 256)
  assert.equal(Gen.acceptLimit(62), 248)
  assert.equal(Gen.acceptLimit(94), 188)
})

test("parseOd reads od output and rejects anything else", () => {
  assert.deepEqual([...Gen.parseOd("   0  17 255\n  4\n")], [0, 17, 255, 4])
  assert.deepEqual([...Gen.parseOd("")], [])
  assert.equal(Gen.parseOd("1 256"), null)
  assert.equal(Gen.parseOd("1 -2"), null)
  assert.equal(Gen.parseOd("od: /dev/urandom: Permission denied"), null)
})

test("generateAll gives three strings of the right length and alphabet", () => {
  for (let run = 0; run < 200; run++) {
    const v = Gen.generateAll(bytes(Gen.BYTES_PER_READ))
    assert.ok(v, "1024 bytes should always be enough")
    Gen.KINDS.forEach((k, i) => {
      assert.equal(v[i].length, k.length)
      for (const ch of v[i]) assert.ok(k.charset.includes(ch), `${ch} not in set ${i}`)
    })
  }
})

test("rejected bytes are skipped, not wrapped", () => {
  // 188..255 must never be used for the printable set.
  const r = Gen.draw([255, 188, 200, 0, 187], 0, Gen.PRINTABLE, 2)
  assert.deepEqual({ ...r }, { value: Gen.PRINTABLE[0] + Gen.PRINTABLE[187 % 94], next: 5 })
})

test("running out of bytes returns null so the caller reads more", () => {
  assert.equal(Gen.generateAll(bytes(100)), null)
  assert.equal(Gen.draw([250, 251], 0, Gen.ALNUM, 1), null)
  assert.equal(Gen.generateAll([]), null)
})

test("every character is equally likely (chi-square)", () => {
  for (const k of Gen.KINDS) {
    const n = k.charset.length
    const counts = new Array(n).fill(0)
    let total = 0
    while (total < n * 2000) {
      const r = Gen.draw(bytes(4096), 0, k.charset, 1024)
      if (!r) continue
      for (const ch of r.value) counts[k.charset.indexOf(ch)]++
      total += r.value.length
    }
    const expected = total / n
    const chi = counts.reduce((s, c) => s + (c - expected) ** 2 / expected, 0)
    // Mean is n-1; mean + 6 standard deviations is far above it, so a fair
    // generator essentially never fails while a skewed one (e.g. plain
    // modulo on the printable set) fails by thousands.
    const bound = n - 1 + 6 * Math.sqrt(2 * (n - 1))
    assert.ok(chi < bound, `${k.name}: chi-square ${chi.toFixed(1)} >= ${bound.toFixed(1)}`)
  }
})
