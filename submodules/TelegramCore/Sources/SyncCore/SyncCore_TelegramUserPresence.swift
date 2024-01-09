import Postbox

public enum UserPresenceStatus: Comparable, PostboxCoding {
    private struct SortKey: Comparable {
        var major: Int
        var minor: Int32
        
        init(major: Int, minor: Int32) {
            self.major = major
            self.minor = minor
        }
        
        static func <(lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            return lhs.minor < rhs.minor
        }
    }
    
    case none
    case hidden
    case present(until: Int32)
    case recently
    case lastWeek
    case lastMonth
    
    private var sortKey: SortKey {
        switch self {
        case let .present(until):
            return SortKey(major: 6, minor: until)
        case .hidden:
            return SortKey(major: 5, minor: 0)
        case .recently:
            return SortKey(major: 4, minor: 0)
        case .lastWeek:
            return SortKey(major: 3, minor: 0)
        case .lastMonth:
            return SortKey(major: 2, minor: 0)
        case .none:
            return SortKey(major: 1, minor: 0)
        }
    }
    
    public static func <(lhs: UserPresenceStatus, rhs: UserPresenceStatus) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }
    
    public init(decoder: PostboxDecoder) {
        switch decoder.decodeInt32ForKey("v", orElse: 0) {
        case 0:
            self = .none
        case 1:
            self = .present(until: decoder.decodeInt32ForKey("t", orElse: 0))
        case 2:
            self = .recently
        case 3:
            self = .lastWeek
        case 4:
            self = .lastMonth
        case 5:
            self = .hidden
        default:
            self = .none
        }
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        switch self {
        case .none:
            encoder.encodeInt32(0, forKey: "v")
        case let .present(timestamp):
            encoder.encodeInt32(1, forKey: "v")
            encoder.encodeInt32(timestamp, forKey: "t")
        case .recently:
            encoder.encodeInt32(2, forKey: "v")
        case .lastWeek:
            encoder.encodeInt32(3, forKey: "v")
        case .lastMonth:
            encoder.encodeInt32(4, forKey: "v")
        case .hidden:
            encoder.encodeInt32(5, forKey: "v")
        }
    }
}

public final class TelegramUserPresence: PeerPresence, Equatable {
    public let status: UserPresenceStatus
    public let lastActivity: Int32
    
    public init(status: UserPresenceStatus, lastActivity: Int32) {
        self.status = status
        self.lastActivity = lastActivity
    }
    
    public init(decoder: PostboxDecoder) {
        self.status = UserPresenceStatus(decoder: decoder)
        self.lastActivity = decoder.decodeInt32ForKey("la", orElse: 0)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        self.status.encode(encoder)
        encoder.encodeInt32(self.lastActivity, forKey: "la")
    }
    
    public static func ==(lhs: TelegramUserPresence, rhs: TelegramUserPresence) -> Bool {
        return lhs.status == rhs.status && lhs.lastActivity == rhs.lastActivity
    }
    
    public func isEqual(to: PeerPresence) -> Bool {
        if let to = to as? TelegramUserPresence {
            return self == to
        } else {
            return false
        }
    }
}
