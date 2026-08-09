import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) var auth

    @State private var isRegister  = false
    @State private var username    = ""
    @State private var password    = ""
    @State private var nickname    = ""
    @State private var loading     = false
    @State private var errorMsg    = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Logo ──────────────────────────────────
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.indigo, .purple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("PrepDot")
                        .font(.largeTitle.bold())
                    Text("你的 AI 面试记忆助手")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 48)

                // ── 表单 ──────────────────────────────────
                VStack(spacing: 14) {
                    if isRegister {
                        FloatingTextField(icon: "person.fill", placeholder: "昵称（选填）", text: $nickname)
                    }
                    FloatingTextField(icon: "at", placeholder: "用户名", text: $username)
                        .textInputAutocapitalization(.never)
                    FloatingTextField(icon: "lock.fill", placeholder: "密码（至少6位）",
                                      text: $password, isSecure: true)
                }
                .padding(.horizontal, 28)

                // ── 错误提示 ──────────────────────────────
                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                        .padding(.horizontal, 28)
                }

                // ── 主按钮 ────────────────────────────────
                Button(action: submit) {
                    Group {
                        if loading {
                            ProgressView().tint(.white)
                        } else {
                            Text(isRegister ? "注 册" : "登 录")
                                .fontWeight(.semibold)
                                .tracking(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSubmit ? Color.indigo : Color.indigo.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmit || loading)
                .padding(.horizontal, 28)
                .padding(.top, 24)

                // ── 切换注册/登录 ──────────────────────────
                Button(action: { isRegister.toggle(); errorMsg = "" }) {
                    HStack(spacing: 4) {
                        Text(isRegister ? "已有账号？" : "还没有账号？")
                            .foregroundColor(.secondary)
                        Text(isRegister ? "去登录" : "去注册")
                            .foregroundColor(.indigo)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
                .padding(.top, 16)

                Spacer()
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    private func submit() {
        errorMsg = ""
        loading = true
        Task {
            do {
                let response: AuthResponse
                if isRegister {
                    response = try await APIService.shared.register(
                        username: username.trimmingCharacters(in: .whitespaces),
                        password: password,
                        nickname: nickname.trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    response = try await APIService.shared.login(
                        username: username.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
                let resp = response
                await MainActor.run { auth.login(with: resp) }
            } catch {
                await MainActor.run { errorMsg = error.localizedDescription }
            }
            await MainActor.run { loading = false }
        }
    }
}

// MARK: - 带图标的输入框组件
struct FloatingTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.indigo)
                .frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
