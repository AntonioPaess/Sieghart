import Foundation

/// Read Aloud's v2 request checksum. Parameters verified against msedge-tts
/// 0.4.1 and edge-tts 7.3.1; arithmetic is explicitly modulo 2^32.
/// This compact round implementation uses no external runtime or library.
enum EdgeSpeechToken {
    static let client = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let initial: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
    private static let seed: [UInt32] = [0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2]
    private static let schedule: [UInt32] = [0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564]
    private static let constants: [UInt32] = [0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA, 0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070, 0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2]
    private static let coefficients: [UInt32] = [0xE82E91B1, 0xB32700D0, 0x44DE24C6, 0x88DFF51D, 0x3BEB65BC, 0x29514038, 0xC89C5933, 0xB328CBDF, 0x8D1EC211, 0xD405B4D5, 0x314EF5D5, 0x26E55F3C, 0xE92491B1, 0x607801C6, 0xF0A5B9D5, 0x82B2C1FB, 0x06064CF3, 0xFA51A3DA, 0xDA79FA60, 0x207CC464, 0xBED20560, 0x3C3C74F3, 0x89F9C9F8, 0xD2D14B61, 0x35FA38C6, 0xBB04A2C1, 0xCB49E3C6, 0xC5626167]
    private static func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    private static func swap(_ x: UInt32) -> UInt32 { rotate(x, 16) }
    private static func s0(_ x: UInt32) -> UInt32 { rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3) }
    private static func s1(_ x: UInt32) -> UInt32 { rotate(x, 17) ^ rotate(x, 19) ^ (x >> 10) }
    private static func expand(_ words: inout [UInt32]) {
        while words.count < 64 {
            let i = words.count
            words.append(s1(words[i - 2]) &+ words[i - 7] &+ s0(words[i - 15]) &+ words[i - 16])
        }
    }
    private static func rounds(_ state: [UInt32], _ words: [UInt32], from start: Int = 0) -> [UInt32] {
        var v = state
        for i in start..<64 {
            let e = v[4], a = v[0]
            let bigE = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let bigA = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
            let ch = v[6] ^ (e & (v[5] ^ v[6]))
            let maj = (a & v[1]) | (v[2] & (a | v[1]))
            let k: UInt32 = start == 14 && i == 14 ? 0xC9DC06A7 : constants[i]
            let t = v[7] &+ bigE &+ ch &+ k &+ words[i]
            v = [t &+ bigA &+ maj, a, v[1], v[2], v[3] &+ t, e, v[5], v[6]]
        }
        return v
    }
    private static func word(_ bytes: [UInt8], _ offset: Int, little: Bool = false) -> UInt32 {
        var result: UInt32 = 0
        for i in 0..<4 {
            let shift = UInt32((little ? i : 3 - i) * 8)
            result |= UInt32(bytes[offset + i]) << shift
        }
        return result
    }
    static func value(at date: Date = Date()) -> String {
        let seconds = UInt64(max(0, date.timeIntervalSince1970)) + 11_644_473_600
        let ticks = (seconds / 300) * 300 * 10_000_000
        let bytes = Array((String(ticks) + client).utf8)
        var first = Array(repeating: UInt32(0), count: 14)
        first += [UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2]), word(bytes, 3)]
        for i in 16..<30 {
            var x = schedule[i - 16]
            if i - 2 >= 14 { x = x &+ (s1(first[i - 2]) ^ (i == 16 ? 0x000B92C0 : 0)) }
            if i - 7 >= 14 { x = x &+ first[i - 7] }
            if i - 15 >= 14 { x = x &+ (s0(first[i - 15]) ^ (i == 29 ? 0x059C0B80 : 0)) }
            first.append(x)
        }
        first.append(s1(first[28]) &+ first[23] &+ s0(first[15]) &+ first[14] &+ 0xC9DC06A7 &- constants[14])
        expand(&first)
        var state = zip(initial, rounds(seed, first, from: 14)).map { $0 &+ $1 }
        let length = 57 + bytes.count
        var padded = Array(bytes.dropFirst(7)) + [0x80]
        padded += Array(repeating: 0, count: (55 - length % 64 + 64) % 64)
        let bits = UInt64(length * 8)
        padded += (0..<8).reversed().map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        for offset in stride(from: 0, to: padded.count, by: 64) {
            var words = stride(from: offset, to: offset + 64, by: 4).map { word(padded, $0) }
            expand(&words)
            state = zip(state, rounds(state, words)).map { $0 &+ $1 }
        }
        let digest = state.flatMap { x in (0..<4).reversed().map { UInt8(truncatingIfNeeded: x >> ($0 * 8)) } }
        let keys = [word(digest, 0, little: true) | 1, word(digest, 4, little: true) | 1]
        let factors = keys.map { $0 &* 0x82893933 }
        var terms: [UInt32] = [], offsets: [UInt32] = []
        for i in 0..<14 { terms.append(coefficients[i * 2] &* factors[i % 2]); offsets.append(coefficients[i * 2 + 1]) }
        var input: [UInt8] = [0] + bytes
        input += Array(repeating: 0, count: (8 - input.count % 8) % 8)
        for i in 0..<(input.count / 4) {
            let x = word(input, i * 4, little: true)
            var t = x &* keys[i % 2]
            var o = swap(x) &* (i % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if i == 0 { t = t &+ (0xF2F90B1A &* factors[0]); o = o &+ 0x0B1A0000 }
            terms.append(t); offsets.append(o)
        }
        var swapAcc: UInt32 = 0, swapLast: UInt32 = 0, running: UInt32 = 0, acc: UInt32 = 0
        for i in stride(from: 0, to: terms.count, by: 2) {
            let x = terms[i], y = terms[i + 1]
            var q = swap(offsets[i] &+ x) &* 0x76F50F34
            swapAcc = swapAcc &+ (swap(q) &* 0xC3EFEA97 &+ q)
            q = swap(offsets[i + 1] &+ y) &* 0x1881CE3C
            swapLast = swap(q) &* 0x35BD1EC9 &+ q
            swapAcc = swapAcc &+ swapLast
            running = running &* keys[0] &+ x
            for f: UInt32 in [0xCF98B111, 0x87085B9F, 0x12CEB96D, 0x257E1D83] { running = swap(running) &* f }
            acc = acc &+ running
            running = running &* keys[1] &+ y
            for f: UInt32 in [0xA27416F5, 0xD38396FF, 0x7C932B89, 0xBFA49F69] { running = swap(running) &* f }
            acc = acc &+ running
        }
        let checksum = [swapLast ^ running, swapAcc ^ acc].flatMap { x in
            (0..<4).map { UInt8(truncatingIfNeeded: x >> ($0 * 8)) }
        }
        func hex(_ values: [UInt8]) -> String { values.map { String(format: "%02X", $0) }.joined() }
        return hex(checksum) + "-" + hex(digest)
    }
}
