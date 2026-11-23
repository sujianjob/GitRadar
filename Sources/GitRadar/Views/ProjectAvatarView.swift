import AppKit
import SwiftUI

struct ProjectAvatarView: View {
    let name: String
    let monogram: String
    let iconPath: String?
    let techStack: ProjectTechStack
    var size: CGFloat = 36

    init(repo: GitRepository, size: CGFloat = 36) {
        self.name = repo.name
        self.monogram = repo.monogram
        self.iconPath = repo.projectIconPath
        self.techStack = repo.techStack
        self.size = size
    }

    init(starredRepo: StarredRepository, localIconPath: String? = nil, size: CGFloat = 36) {
        self.name = starredRepo.name
        self.monogram = starredRepo.monogram
        self.iconPath = localIconPath ?? starredRepo.cachedAvatarPath
        self.techStack = starredRepo.techStack
        self.size = size
    }

    init(rankedRepo: RankedRepository, localIconPath: String? = nil, size: CGFloat = 36) {
        self.name = rankedRepo.name
        self.monogram = rankedRepo.monogram
        self.iconPath = localIconPath ?? rankedRepo.cachedAvatarPath
        self.techStack = rankedRepo.techStack
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let iconPath = iconPath,
               let nsImage = NSImage(contentsOfFile: iconPath) {
                // 1. 优先展示真实项目图标或远程组织/作者官方头像
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                    )
            } else {
                // 2. 无图标文件时：按项目名称 Hash + 技术栈生成独一无二的专属徽标
                let palette = AppTheme.palette(for: name)
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(palette.bg)
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                .stroke(palette.fg.opacity(0.22), lineWidth: 1)
                        )

                    Text(monogram)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.fg)
                }
            }

            // 右下角微型技术栈角标（清晰区分 Swift / Python / TS / Go / Rust 等不同项目类型）
            if size >= 32 {
                Text(techStack.shortTag)
                    .font(.system(size: max(7, size * 0.19), weight: .bold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(AppTheme.hairlineBorder, lineWidth: 0.8)
                    )
                    .foregroundStyle(.secondary)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size, height: size)
    }
}
