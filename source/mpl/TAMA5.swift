// Copyright (c) 2013-2016 Jeffrey Pfau (mGBA); Swift translation and changes by EmuCore.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Bandai TAMA5 (Game de Hakken!! Tamagotchi Osutchi to Mesutchi): every access goes
/// through nibble registers at 0xA000 (data) / 0xA001 (register select). It fronts
/// 32 bytes of RAM and a TAMA6 clock kept as BCD nibbles (seconds up to years).
/// Translated from mGBA's src/gb/mbc/tama5.c (register map, commands, read/write handling,
/// register masks), so this file stays under mGBA's licence, the MPL 2.0: its source must be
/// published with the app (THIRD_PARTY_NOTICES.md). The TAMA6 calendar (tickSecond) is EmuCore's.
struct TAMA5State: Codable {
    var selected: UInt8 = 0
    var registers = [UInt8](repeating: 0, count: 8)
    /// Timer page: s1, s10, m1, m10, h1, h10, weekday, d1, d10, mo1, mo10, y1, y10, page.
    var timer: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0]
    /// Alarm page: index 0xA = 24-hour mode, 0xB = years since the last leap year.
    var alarm = [UInt8](repeating: 0, count: 14)
    var free0 = [UInt8](repeating: 0, count: 14), free1 = [UInt8](repeating: 0, count: 14)
    var timerEnabled = true
    var subsecondCycles = 0

    var isValid: Bool {
        registers.count == 8 && [timer, alarm, free0, free1].allSatisfy { $0.count == 14 }
    }

    /// Valid bits per TAMA6 register (timer page, then alarm page).
    static let masks: [UInt8] = [0xF, 0x7, 0xF, 0x7, 0xF, 0x3, 0x7, 0xF, 0x3, 0xF, 0x1, 0xF, 0xF, 0x0,
                                 0x0, 0x0, 0xF, 0x7, 0xF, 0x3, 0x7, 0xF, 0x3, 0x0, 0x1, 0x3, 0x0, 0x0]

    private func bcd(_ low: Int) -> Int { Int(timer[low]) + Int(timer[low + 1]) * 10 }
    private mutating func setBCD(_ low: Int, _ value: Int) { timer[low] = UInt8(value % 10); timer[low + 1] = UInt8(value / 10) }

    /// One second of the TAMA6 calendar.
    mutating func tickSecond() {
        guard timerEnabled else { return }
        var seconds = bcd(0) + 1
        if seconds < 60 { setBCD(0, seconds); return }
        seconds = 0; setBCD(0, 0)
        let minutes = bcd(2) + 1
        if minutes < 60 { setBCD(2, minutes); return }
        setBCD(2, 0)
        let twentyFour = alarm[0xA] & 1 != 0
        // 12-hour mode keeps PM in bit 1 of the hour tens nibble.
        var hour = twentyFour ? bcd(4) : Int(timer[4]) + Int(timer[5] & 1) * 10 + (timer[5] & 2 != 0 ? 12 : 0)
        hour += 1
        if hour < 24 {
            if twentyFour { setBCD(4, hour) } else { timer[4] = UInt8(hour % 12 % 10); timer[5] = UInt8(hour % 12 / 10) | (hour >= 12 ? 2 : 0) }
            return
        }
        timer[4] = 0; timer[5] = 0
        timer[6] = (timer[6] + 1) % 7
        let month = bcd(9), leap = alarm[0xB] & 3 == 0
        let length = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(1, min(month, 12)) - 1]
        let day = bcd(7) + 1
        if day <= length { setBCD(7, day); return }
        setBCD(7, 1)
        if month < 12 { setBCD(9, month + 1); return }
        setBCD(9, 1)
        setBCD(11, (bcd(11) + 1) % 100)
        alarm[0xB] = (alarm[0xB] + 1) & 3
    }
}

extension Cartridge {
    mutating func writeTAMA5(_ a: UInt16, _ v: UInt8) {
        guard var s = tama5, a & 0xE000 == 0xA000 else { return }
        defer { tama5 = s }
        if a & 1 != 0 { s.selected = v; return }
        let reg = Int(s.selected), v = v & 0xF
        guard reg < 8 else { return }
        s.registers[reg] = v
        let r = s.registers
        let address = Int(r[6] << 4 & 0x10 | r[7]), out = r[5] << 4 | r[4]
        switch reg {
        case 0, 1:
            bank1 = Int(r[0] | r[1] << 4)
            romXOffset = (bank1 & romBankMask) * 0x4000
            romYOffset = romXOffset + 0x2000
        case 7:
            switch r[6] >> 1 {
            case 0: if !ram.isEmpty { ram[address % ram.count] = out } // RAM write
            case 2: // clock commands
                switch address {
                case 0x0: s.timerEnabled = false
                case 0x1: s.timerEnabled = true; s.timer[0] = 0; s.timer[1] = 0
                case 0x4: s.timer[2] = out & 0xF; s.timer[3] = out >> 4
                case 0x5: s.timer[4] = out & 0xF; s.timer[5] = out >> 4
                default: break
                }
            case 4: // direct TAMA6 register access: register in WRITE_LO, value in WRITE_HI
                let index = Int(r[4])
                guard index < 0xD else { break }
                switch r[7] {
                case 0: s.timer[index] = r[5] & TAMA5State.masks[index]
                case 2: s.alarm[index] = r[5] & TAMA5State.masks[index + 14]
                case 4: s.free0[index] = r[5]
                case 6: s.free1[index] = r[5]
                default: break
                }
            default: break
            }
        default: break
        }
    }

    func readTAMA5(_ a: UInt16) -> UInt8 {
        guard let s = tama5 else { return 0xFF }
        if a & 1 != 0 { return 0xFF }
        let r = s.registers
        let address = Int(r[6] << 4 & 0x10 | r[7])
        switch s.selected {
        case 0xA: return 0xF1 // ready
        case 0xC, 0xD:
            var value: UInt8 = 0
            switch r[6] >> 1 {
            case 1: value = ram.isEmpty ? 0 : ram[address % ram.count]
            case 2:
                switch address {
                case 0x6: value = s.timer[3] << 4 | s.timer[2] // minutes, BCD
                case 0x7: value = s.timer[5] << 4 | s.timer[4] // hours, BCD
                default: value = UInt8(address)
                }
            case 4:
                let index = Int(r[4])
                if index < 0xD {
                    switch r[7] {
                    case 1: value = s.timer[index]
                    case 3: value = s.alarm[index]
                    case 5: value = s.free0[index]
                    case 7: value = s.free1[index]
                    default: break
                    }
                }
            default: break
            }
            if s.selected == 0xD { value >>= 4 }
            return value & 0xF | 0xF0
        default: return 0xF1
        }
    }
}
