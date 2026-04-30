import Foundation

struct Preset: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var order: [UInt8]      // ball position sequence, values 1...28
    var isRandom: Bool
    var shuffle: Bool
    var interval: Int
    var topSpeed: Int
    var bottomSpeed: Int
    var frequency: Int
    var shortAngle: Int

    init(
        id: UUID = UUID(),
        name: String,
        order: [UInt8],
        isRandom: Bool = true,
        shuffle: Bool = false,
        interval: Int = 0,
        topSpeed: Int = 60,
        bottomSpeed: Int = 60,
        frequency: Int = 7,
        shortAngle: Int = 27
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.isRandom = isRandom
        self.shuffle = shuffle
        self.interval = interval
        self.topSpeed = topSpeed
        self.bottomSpeed = bottomSpeed
        self.frequency = frequency
        self.shortAngle = shortAngle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case order
        case isRandom
        case shuffle
        case interval
        case topSpeed
        case bottomSpeed
        case frequency
        case shortAngle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        order = try c.decode([UInt8].self, forKey: .order)
        isRandom = try c.decode(Bool.self, forKey: .isRandom)
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 0
        topSpeed = try c.decode(Int.self, forKey: .topSpeed)
        bottomSpeed = try c.decode(Int.self, forKey: .bottomSpeed)
        frequency = try c.decode(Int.self, forKey: .frequency)
        shortAngle = try c.decode(Int.self, forKey: .shortAngle)
    }

    var orderText: String {
        order.map(String.init).joined(separator: " ")
    }
}
