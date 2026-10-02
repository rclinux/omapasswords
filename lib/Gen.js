.pragma library

// Turns bytes from /dev/urandom into the three Prime Passwords strings.
//
// QML's JavaScript has no secure random source (Math.random is not one), so
// the panel reads raw bytes from /dev/urandom and hands them here. Each byte is
// mapped to a character by rejection sampling: bytes at or above the largest
// multiple of the set size are thrown away, so every character in a set has
// exactly equal odds. The sets and lengths match the Prime Passwords desktop
// app (internal/gen/gen.go).

var HEX = "0123456789ABCDEF"
var ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
var PRINTABLE = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

var KINDS = [
  { name: "64 hexadecimal characters", charset: HEX, length: 64 },
  { name: "63 printable ASCII characters", charset: PRINTABLE, length: 63 },
  { name: "63 letters and digits", charset: ALNUM, length: 63 }
]

// How many random bytes to ask for at once. About 215 are needed on average;
// the rest is margin so a second read is almost never required.
var BYTES_PER_READ = 1024

// Entropy of one string of kind k, in bits.
function bits(k) {
  return k.length * Math.log2(k.charset.length)
}

// Bytes below this value are used; the rest are rejected.
function acceptLimit(setSize) {
  return 256 - (256 % setSize)
}

// Parses `od -An -v -tu1` output into an array of byte values.
// Returns null if anything in it is not a byte.
function parseOd(text) {
  var out = []
  var parts = String(text).split(/\s+/)
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "") continue
    if (!/^\d{1,3}$/.test(parts[i])) return null
    var n = parseInt(parts[i], 10)
    if (n > 255) return null
    out.push(n)
  }
  return out
}

// Builds one string from bytes, starting at index `start`.
// Returns { value, next } or null if the bytes ran out first.
function draw(bytes, start, charset, length) {
  var limit = acceptLimit(charset.length)
  var chars = []
  var i = start
  while (chars.length < length) {
    if (i >= bytes.length) return null
    var b = bytes[i++]
    if (b < limit) chars.push(charset.charAt(b % charset.length))
  }
  return { value: chars.join(""), next: i }
}

// Builds all three strings from one pool of bytes.
// Returns an array of strings in KINDS order, or null if more bytes are needed.
function generateAll(bytes) {
  var values = []
  var pos = 0
  for (var k = 0; k < KINDS.length; k++) {
    var r = draw(bytes, pos, KINDS[k].charset, KINDS[k].length)
    if (r === null) return null
    values.push(r.value)
    pos = r.next
  }
  return values
}
