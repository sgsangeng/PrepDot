import SwiftUI

@Observable
class AuthManager {
    static let shared = AuthManager()

    var isLoggedIn: Bool = false
    var nickname: String = ""
    var avatarColor: String = "#6366F1"
    var studyTarget: Int = 20
    var userId: Int = 0

    private let defaults = UserDefaults.standard

    init() {
        if let token = defaults.string(forKey: "jwt_token"), tokenIsValid(token) {
            isLoggedIn = true
            nickname     = defaults.string(forKey: "nickname") ?? ""
            avatarColor  = defaults.string(forKey: "avatarColor") ?? "#6366F1"
            let savedTarget = defaults.integer(forKey: "studyTarget")
            studyTarget  = savedTarget > 0 ? savedTarget : 20
            userId       = defaults.integer(forKey: "userId")
            APIService.shared.token = token
        } else {
            clearStoredSession()
        }
    }

    /// 启动时先在本地检查 JWT 的 exp，避免拿过期令牌进入主界面后一直加载。
    private func tokenIsValid(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = json["exp"] as? TimeInterval else { return false }
        return Date(timeIntervalSince1970: expiry) > Date()
    }

    private func clearStoredSession() {
        ["jwt_token", "username", "nickname", "avatarColor", "studyTarget", "userId"]
            .forEach(defaults.removeObject(forKey:))
    }

    func login(with auth: AuthResponse) {
        defaults.set(auth.token,       forKey: "jwt_token")
        defaults.set(auth.username,    forKey: "username")
        defaults.set(auth.nickname,    forKey: "nickname")
        defaults.set(auth.avatarColor, forKey: "avatarColor")
        defaults.set(auth.studyTarget, forKey: "studyTarget")
        defaults.set(auth.userId,      forKey: "userId")

        APIService.shared.token = auth.token
        nickname    = auth.nickname
        avatarColor = auth.avatarColor
        studyTarget = auth.studyTarget
        userId      = auth.userId
        isLoggedIn  = true
    }

    func logout() {
        clearStoredSession()
        APIService.shared.token = nil
        nickname = ""
        avatarColor = "#6366F1"
        studyTarget = 20
        userId = 0
        isLoggedIn = false
    }
}
