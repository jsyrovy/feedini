import CryptoKit
import Foundation

/// IDs derived from what identifies a thing, so that two devices that download the same feed get the same feed and
/// article IDs (and one library can be merged into another by ID). A UUID of version 8 from the first 16 bytes of
/// the SHA-256 of its parts. Folders, stories and topics keep random IDs.
enum StableID {
    /// The feed at the address, compared as `FeedSubscriber.isSame` compares addresses.
    static func feed(url: URL) -> UUID {
        make("feed", FeedSubscriber.normalizedAddress(url))
    }

    /// The article with the key (`Article.key`) in the feed.
    static func article(feed: Feed.ID, key: String) -> UUID {
        make("article", feed.uuidString, key)
    }

    private static func make(_ parts: String...) -> UUID {
        // The unit separator can't be in an address or a feed's key, so different parts can't give the same text.
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80  // version 8
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant RFC 9562
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
