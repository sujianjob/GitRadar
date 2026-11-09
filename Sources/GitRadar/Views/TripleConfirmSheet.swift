import SwiftUI

struct TripleConfirmSheet: View {
    let confirmation: PendingGitConfirmation
    let onCancel: () -> Void
    let onConfirmedExecute: () -> Void

    @State private var currentStep: Int = 1 // 仅在 isBatchTripleConfirm == true 时使用 1 -> 2 -> 3

    var body: some View {
        if confirmation.isBatchTripleConfirm {
            tripleConfirmBody
        } else {
            singleConfirmBody
        }
    }

    // MARK: - 单项目操作：简洁单次确认弹窗（点一次「确认执行」即可）
    private var singleConfirmBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: confirmation.isDestructive ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(confirmation.isDestructive ? AppTheme.statusDirty : AppTheme.accent)

                Text(confirmation.title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("目标仓库：")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(confirmation.targetDescription)
                        .font(.system(size: 11.5, weight: .semibold))
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("执行命令：")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(confirmation.gitCommandPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.hairlineBorder, lineWidth: 1))
                }

                Text(confirmation.step1Warning)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.subtleSurface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.hairlineBorder, lineWidth: 1))

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("确认执行") {
                    onConfirmedExecute()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(confirmation.isDestructive ? AppTheme.statusDanger : AppTheme.accent)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    // MARK: - 批量操作：三次风险确认弹窗（1/3 -> 2/3 -> 3/3）
    private var tripleConfirmBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: confirmation.isDestructive ? "exclamationmark.octagon.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(confirmation.isDestructive ? AppTheme.statusDanger : AppTheme.statusDirty)

                VStack(alignment: .leading, spacing: 2) {
                    Text("批量操作三次确认 · \(confirmation.title)")
                        .font(.system(size: 15, weight: .bold))
                    Text("批量操作涉及多个仓库，请依次完成以下 3 步风险确认后执行")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("作用目标：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)
                    Text(confirmation.targetDescription)
                        .font(.system(size: 12, weight: .medium))
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("执行命令：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)
                    Text(confirmation.gitCommandPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(AppTheme.subtleSurface))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.hairlineBorder, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                riskStepRow(
                    stepNumber: 1,
                    title: "第 1 次确认：核对目标范围与执行命令",
                    detail: confirmation.step1Warning
                )

                riskStepRow(
                    stepNumber: 2,
                    title: "第 2 次确认：评估本地代码与分支冲突风险",
                    detail: confirmation.step2Warning
                )

                riskStepRow(
                    stepNumber: 3,
                    title: "第 3 次确认：最终执行授权",
                    detail: confirmation.step3Warning
                )
            }

            Divider()

            HStack {
                Text("当前进度：第 \(currentStep) / 3 次确认")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(currentStep == 3 ? AppTheme.statusDanger : .secondary)

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if currentStep < 3 {
                            currentStep += 1
                        } else {
                            onConfirmedExecute()
                        }
                    }
                } label: {
                    Text(confirmButtonLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(buttonTint)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var confirmButtonLabel: String {
        switch currentStep {
        case 1:
            return "第 1/3 次确认：已核对目标与命令 →"
        case 2:
            return "第 2/3 次确认：已知晓潜在风险 →"
        default:
            return "第 3/3 次最终确认：立即执行"
        }
    }

    private var buttonTint: Color {
        switch currentStep {
        case 1:
            return AppTheme.accent
        case 2:
            return AppTheme.statusDirty
        default:
            return confirmation.isDestructive ? AppTheme.statusDanger : AppTheme.statusDirty
        }
    }

    @ViewBuilder
    private func riskStepRow(stepNumber: Int, title: String, detail: String) -> some View {
        let isCompleted = currentStep > stepNumber
        let isCurrent = currentStep == stepNumber

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        isCompleted ? AppTheme.statusClean :
                        (isCurrent ? AppTheme.statusDirty : Color.secondary.opacity(0.15))
                    )
                    .frame(width: 20, height: 20)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(stepNumber)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent || isCompleted ? .primary : .secondary)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? Color.primary.opacity(0.85) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? AppTheme.statusDirty.opacity(0.08) : AppTheme.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isCurrent ? AppTheme.statusDirty.opacity(0.45) : AppTheme.hairlineBorder,
                    lineWidth: 1
                )
        )
        .opacity(currentStep >= stepNumber ? 1.0 : 0.55)
    }
}
