import Foundation

enum BLEConstants {
    enum UUIDs {
        static let service = "0000FF10-0000-1000-8000-00805F9B34FB"
        static let write = "0000FF11-0000-1000-8000-00805F9B34FB"
        static let notify = "0000FF12-0000-1000-8000-00805F9B34FB"
    }

    enum Packet {
        static let head: [UInt8] = [0x7E, 0x3A]
        static let tail: [UInt8] = [0x0D, 0x0A]
        static let start6: [UInt8] = [0x07, 0x22]
        static let stop: [UInt8] = [0x06, 0x01]
        static let frequency: [UInt8] = [0x03, 0x01]
        static let shortAngle: [UInt8] = [0x04, 0x01]
    }
}

enum TennisCommand {
    static let head = BLEConstants.Packet.head
    static let tail = BLEConstants.Packet.tail

    static let start6 = BLEConstants.Packet.start6
    static let stop = BLEConstants.Packet.stop
    static let frequency = BLEConstants.Packet.frequency
    static let shortAngle = BLEConstants.Packet.shortAngle

    static func packet(cmd: [UInt8], data: [UInt8]) -> Data {
        var bytes: [UInt8] = []
        bytes += head
        bytes += cmd
        bytes += data
        bytes.append(checksum(head: head, cmd: cmd, data: data))
        bytes += tail
        return Data(bytes)
    }

    static func checksum(head: [UInt8], cmd: [UInt8], data: [UInt8]) -> UInt8 {
        var s = 0
        for b in (head + cmd + data) {
            s += Int(b)
        }
        return UInt8(s & 0xFF)
    }

    static func startV6(
        order: [UInt8],
        top: UInt8,
        bottom: UInt8,
        frequency: UInt8,
        shortAngle: UInt8,
        random: Bool,
        startFlag: UInt8
    ) -> Data {
        var route = Array(order.prefix(28))
        if route.count < 28 {
            route += Array(repeating: 0, count: 28 - route.count)
        }
        let data = route + [
            top,
            bottom,
            frequency,
            shortAngle,
            random ? 1 : 0,
            startFlag
        ]
        return packet(cmd: start6, data: data)
    }

    static func stopV6() -> Data {
        packet(cmd: stop, data: [0])
    }

    static func setFrequency(_ f: UInt8) -> Data {
        packet(cmd: frequency, data: [f])
    }

    static func setShortAngle(_ angle: UInt8) -> Data {
        packet(cmd: shortAngle, data: [angle])
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
