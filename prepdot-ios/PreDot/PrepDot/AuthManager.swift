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
        if let token = defaults.string(forKey: "jwt_token"), !token.isEmpty {
            isLoggedIn = true
            nickname     = defaults.string(forKey: "nickname") ?? ""
            avatarColor  = defaults.string(forKey: "avatarColor") ?? "#6366F1"
            let savedTarget = defaults.integer(forKey: "studyTarget")
            studyTarget  = savedTarget > 0 ? savedTarget : 20
            userId       = defaults.integer(forKey: "userId")
            APIService.shared.token = token
        }
    }

    func login(with auth: AuthResponse) {
        defaults.set(auth.token,       forKey: "jwt_token")
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
        defaults.removeObject(forKey: "jwt_token")
        defaults.removeObject(forKey: "nickname")
        APIService.shared.token = nil
        isLoggedIn = false
    }
}
