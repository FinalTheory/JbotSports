import Foundation

struct Preset: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var order: [UInt8]      // ball position sequence, values 1...28
    var isRandom: Bool
    var topSpeed: Int
    var bottomSpeed: Int
    var frequency: Int
    var shortAngle: Int

    init(
        id: UUID = UUID(),
        name: String,
        order: [UInt8],
        isRandom: Bool = true,
        topSpeed: Int = 60,
        bottomSpeed: Int = 60,
        frequency: Int = 7,
        shortAngle: Int = 27
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.isRandom = isRandom
        self.topSpeed = topSpeed
        self.bottomSpeed = bottomSpeed
        self.frequency = frequency
        self.shortAngle = shortAngle
    }

    var orderText: String {
        order.map(String.init).joined(separator: " ")
    }
}
