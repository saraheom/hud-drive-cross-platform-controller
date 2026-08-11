import Foundation

enum HudNotificationKind: String, CaseIterable, Identifiable {
    case calls
    case messages
    case calendar
    case gmail
    case weChat
    case kakaoTalk
    case spotify
    case googleMaps
    case appleMaps
    case waze

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calls: "Calls"
        case .messages: "Messages"
        case .calendar: "Calendar"
        case .gmail: "Gmail"
        case .weChat: "WeChat"
        case .kakaoTalk: "KakaoTalk"
        case .spotify: "Spotify"
        case .googleMaps: "Google Maps"
        case .appleMaps: "Apple Maps"
        case .waze: "Waze"
        }
    }

    var identifiers: [String] {
        switch self {
        case .calls:
            ["com.kivic.call", "com.apple.mobilephone"]
        case .messages:
            ["com.kivic.sms", "com.apple.MobileSMS"]
        case .calendar:
            ["com.apple.mobilecal"]
        case .gmail:
            ["com.kivic.email", "com.google.Gmail"]
        case .weChat:
            ["com.kivic.wechat", "com.tencent.xin"]
        case .kakaoTalk:
            ["com.kivic.kakaotalk", "com.iwilab.KakaoTalk"]
        case .spotify:
            ["com.kivic.music", "com.spotify.client"]
        case .googleMaps:
            ["com.google.Maps"]
        case .appleMaps:
            ["com.apple.Maps"]
        case .waze:
            ["com.waze.iphone"]
        }
    }

    var hudIcon: Int32 {
        switch self {
        case .calls: 1
        case .messages: 2
        case .spotify: 3
        case .gmail: 4
        case .kakaoTalk: 6
        case .weChat: 9
        default: 0
        }
    }

    var textColor: Int32 {
        switch self {
        case .spotify: -12_996_114
        case .kakaoTalk: -335_616
        default: -1
        }
    }
}
